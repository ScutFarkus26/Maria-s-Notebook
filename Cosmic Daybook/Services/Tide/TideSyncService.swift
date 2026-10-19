// TideSyncService.swift
// When the Tide sharing runs, and what Settings shows about it.

import CoreData
import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

/// The one owner of the sharing in the app: the saved address, Danny's
/// choices, the status line Settings shows, and when a run happens. On the
/// Mac (`TideSyncPolicy.live`) a run happens when the notebook opens or comes
/// to the front, about thirty seconds after a to-do changes, and every three
/// minutes while the notebook is the active app and Tide answers (ten while it
/// doesn't). Nothing runs in the background or on iPhone and iPad; there,
/// Settings says the Mac does this.
///
/// Only the waits are ever cancelled. A run, once started, finishes: cut
/// off between `add_action` and saving its link, it would leave an action in
/// Tide that only its notebook line can tie back.
@Observable
@MainActor
final class TideSyncService {
    static let shared = TideSyncService()

    /// Danny's choices; each change is saved and starts a run.
    var settings: TideSyncSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            requestRun(after: timing.settingsChange)
        }
    }

    private(set) var statusMessage: String
    private(set) var statusDetails: String?
    private(set) var statusIsProblem = false
    /// The first run's matches, while they wait for Danny.
    private(set) var proposal: TideFirstRunProposal?
    /// My Classrooms' lists that feed Tide's Next Actions, from the last read.
    private(set) var lists: [TideList] = []
    /// Each list's headings, from the last read.
    private(set) var headings: [String: [String]] = [:]
    var hasAddress: Bool { address != nil }
    /// True for the whole of a run, so a second can't start beside it.
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?

    let policy: TideSyncPolicy
    private let defaults: UserDefaults
    private let timing: Timing
    private let keeper: AddressKeeper
    private let shouldDefer: () -> Bool
    private let makeTransport: (TideAddress) -> TideTransport
    private var address: TideAddress?
    private var engine: TideSyncEngine?
    private var store: NotebookTideTodoStore?
    /// Sync Now (or Link and Start) pressed during a run: one more follows it.
    private var runAgain = false
    /// The matches Danny confirmed during a run, for the run that follows it.
    private var matchesForNextRun: [TideFirstRunProposal.Match]?
    /// A to-do changed during a run: another follows, after the usual wait.
    private var followUp = false
    private var pending: Task<Void, Never>?
    private var repeating: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Whether the last run found Tide closed, so the next waits longer.
    private var statusIsAway = false
    /// When the last run ended, so coming to the front right after one
    /// doesn't start another.
    private var lastRunEnded: ContinuousClock.Instant?

    private static let logger = Logger(subsystem: "CosmicDaybook", category: "TideSync")

    init(
        defaults: UserDefaults = .standard,
        policy: TideSyncPolicy = .current,
        timing: Timing = Timing(),
        keeper: AddressKeeper = .keychain,
        shouldDefer: @escaping () -> Bool = { EnergyPolicy.shared.shouldDeferMaintenance },
        makeTransport: @escaping (TideAddress) -> TideTransport = { TideHTTPTransport(address: $0) }
    ) {
        self.defaults = defaults
        self.policy = policy
        self.timing = timing
        self.keeper = keeper
        self.shouldDefer = shouldDefer
        self.makeTransport = makeTransport
        settings = TideSyncSettings(defaults: defaults)
        lastSyncAt = TideSyncState(defaults: defaults).lastSyncAt
        statusMessage = TideSyncMessages.off
        if policy == .live {
            do {
                address = try keeper.load()
            } catch {
                Self.logger.error("Tide address unreadable: \(String(describing: error), privacy: .public)")
            }
        }
        showIdleStatus()
    }

    // MARK: - Starting

    /// Starts the runs on the Mac, once, from the app-wide services. Binds to
    /// the notebook's own store, never the Sample Class.
    func start(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        guard policy == .live, store == nil else { return }
        store = NotebookTideTodoStore(context: context, saveCoordinator: saveCoordinator)
        observeTodos(in: context)
        #if os(macOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startRepeating() }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRepeating() }
        })
        if NSApplication.shared.isActive { startRepeating() }
        #endif
        requestRun(after: timing.start)
    }

    private func observeTodos(in context: NSManagedObjectContext) {
        let names: Set<String> = ["TodoItem"]
        let key = PersistentHistoryProcessor.changedEntityNamesKey
        let center = NotificationCenter.default
        // Heard as it is posted, on the view context's own (main) queue, so a
        // change the sync makes is heard while the store says it is writing.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: nil
        ) { [weak self] note in
            guard Thread.isMainThread, !ManagedObjectChangeScope.touched(names, in: note.userInfo).isEmpty
            else { return }
            MainActor.assumeIsolated { self?.todosChanged() }
        })
        observers.append(center.addObserver(
            forName: .presentationDataDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let changed = note.userInfo?[key] as? Set<String>, !changed.isDisjoint(with: names) else { return }
            MainActor.assumeIsolated { self?.todosChanged() }
        })
    }

    /// A to-do changed here or arrived from iCloud. The sync's own changes
    /// don't start another run; one made during a run starts one after it.
    private func todosChanged() {
        guard settings.isOn, store?.isWriting == false else { return }
        if isSyncing {
            followUp = true
        } else {
            requestRun(after: timing.change)
        }
    }

    // MARK: - Runs

    /// Runs now, from Settings' Sync Now.
    func syncNow() async {
        pending?.cancel()
        await runOnce(userInitiated: true)
    }

    /// Links the matches Danny kept, and starts sharing.
    func confirmFirstRun(_ matches: [TideFirstRunProposal.Match]) async {
        pending?.cancel()
        await runOnce(userInitiated: true, confirming: matches)
    }

    /// One run `delay` from now; a later request replaces an earlier one.
    /// Cancelling replaces only the wait: the run starts in its own task.
    private func requestRun(after delay: Duration) {
        guard policy == .live, store != nil else { return }
        pending?.cancel()
        pending = Task { [weak self, timing] in
            try? await Task.sleep(for: delay, tolerance: timing.tolerance)
            guard !Task.isCancelled else { return }
            self?.startRun()
        }
    }

    /// Starts a self-started run in a task of its own, which no wait's
    /// cancelling reaches.
    private func startRun() {
        Task { await runOnce(userInitiated: false) }
    }

    private func startRepeating() {
        guard policy == .live, repeating == nil else { return }
        repeating = Task { [weak self, timing] in
            let recent = self?.lastRunEnded.map { ContinuousClock.now - $0 < .seconds(60) } ?? false
            if !recent { self?.startRun() }
            while !Task.isCancelled {
                let wait = self?.statusIsAway == true ? timing.intervalWhileAway : timing.interval
                try? await Task.sleep(for: wait, tolerance: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.startRun()
            }
        }
    }

    private func stopRepeating() {
        repeating?.cancel()
        repeating = nil
    }

    /// One run at a time: two at once could send the same to-do twice. The
    /// check and the claim happen with no suspension between them, on the
    /// main actor, and the work runs in a task of its own, so a caller's
    /// cancelling never cuts it short.
    private func runOnce(userInitiated: Bool, confirming matches: [TideFirstRunProposal.Match]? = nil) async {
        guard !isSyncing else {
            if userInitiated { runAgain = true }
            if let matches { matchesForNextRun = matches }
            return
        }
        isSyncing = true
        let work = Task { await runLoop(userInitiated: userInitiated, confirming: matches) }
        await work.value
    }

    private func runLoop(userInitiated: Bool, confirming matches: [TideFirstRunProposal.Match]?) async {
        await perform(userInitiated: userInitiated, confirming: matches)
        while runAgain {
            runAgain = false
            let confirmed = matchesForNextRun
            matchesForNextRun = nil
            await perform(userInitiated: true, confirming: confirmed)
        }
        isSyncing = false
        lastRunEnded = .now
        if followUp {
            followUp = false
            requestRun(after: timing.change)
        }
    }

    private func perform(userInitiated: Bool, confirming matches: [TideFirstRunProposal.Match]?) async {
        guard policy == .live else { return showIdleStatus() }
        guard settings.isOn, let engine = currentEngine() else { return showIdleStatus() }
        if !userInitiated, shouldDefer() { return }
        if matches != nil || statusMessage == TideSyncMessages.off || statusMessage == TideSyncMessages.needsAddress {
            show(TideSyncMessages.syncing)
        }
        let result = if let matches {
            await engine.confirmFirstRun(matches, settings: settings)
        } else {
            await engine.run(settings)
        }
        apply(result, engine: engine)
    }

    private func apply(_ result: TideSyncResult, engine: TideSyncEngine) {
        statusIsAway = false
        if let area = engine.lastArea { showLists(of: area) }
        switch result {
        case .synced(let report):
            proposal = nil
            lastSyncAt = engine.state.lastSyncAt
            show(report)
            if report.tryAgain { followUp = true }
        case .needsFirstRunOK(let proposal):
            self.proposal = proposal
            show(TideSyncMessages.waitingForOK)
        case .stopped(let problem):
            statusIsAway = problem == .tideNotRunning || problem == .timedOut
            show(problem.message, details: problem.detailLines, problem: true)
        }
    }

    private func currentEngine() -> TideSyncEngine? {
        guard let address, let store else { return nil }
        if let engine { return engine }
        let defaults = defaults
        let engine = TideSyncEngine(
            transport: makeTransport(address), store: store, state: TideSyncState(defaults: defaults),
            persist: { $0.save(to: defaults) }
        )
        self.engine = engine
        return engine
    }
}

// MARK: - Settings' actions

extension TideSyncService {
    /// Saves a pasted address. Returns the sentence to show when it can't be used.
    func saveAddress(_ text: String) async -> String? {
        let parsed: TideAddress
        switch TideAddress.parse(text) {
        case .success(let address): parsed = address
        case .failure(let problem): return problem.errorDescription
        }
        guard policy == .live else { return nil }
        do {
            try keeper.save(parsed)
        } catch {
            Self.logger.error("Tide address not saved: \(String(describing: error), privacy: .public)")
            return AppErrorMessages.userMessage(for: error)
        }
        address = parsed
        engine = nil
        await refreshLists(quietly: false)
        requestRun(after: timing.settingsChange)
        return nil
    }

    /// Forgets the address; nothing goes across until a new one is pasted.
    func forgetAddress() {
        do {
            try keeper.delete()
        } catch {
            Self.logger.error("Tide address not removed: \(String(describing: error), privacy: .public)")
        }
        address = nil
        engine = nil
        lists = []
        showIdleStatus()
    }

    /// Reads My Classrooms' lists for the pickers, when Settings opens or
    /// Refresh is pressed. Quietly leaves the status line alone; otherwise
    /// says what went wrong.
    func refreshLists(quietly: Bool = false) async {
        guard policy == .live, let address else { return }
        do {
            showLists(of: try await TideTools(transport: makeTransport(address)).area(TideSyncSettings.area))
            if !quietly, !settings.isOn { show(TideSyncMessages.off) }
        } catch {
            guard !quietly else { return }
            let problem = TideSyncProblem(readingArea: error)
            show(problem.message, details: problem.detailLines, problem: true)
        }
    }
}

// MARK: - Status

extension TideSyncService {
    fileprivate func showLists(of area: TideArea) {
        lists = area.feedingLists.sorted { $0.file < $1.file }
        headings = Dictionary(uniqueKeysWithValues: lists.map { ($0.file, area.headings(of: $0.file)) })
    }

    fileprivate func show(_ report: TideSyncReport) {
        let destination = TideActionLink.listName(ofFile: settings.destinationFile)
        if report.headingGone != nil {
            show(TideSyncMessages.headingGone(report.headingGone, list: destination), problem: true)
        } else if !report.notTicked.isEmpty {
            show(TideSyncMessages.notTicked(report.notTicked), details: report.details, problem: true)
        } else if !report.notSent.isEmpty {
            show(TideSyncMessages.notSent(report.notSent), details: report.details, problem: true)
        } else if report.destinationGone {
            show(TideSyncMessages.destinationGone, problem: true)
        } else if report.tryAgain {
            show(TideSyncMessages.nextTry, details: report.details)
        } else {
            show(TideSyncMessages.upToDate, details: report.details)
        }
    }

    fileprivate func showIdleStatus() {
        switch policy {
        case .notOnThisDevice: show(TideSyncMessages.notOnThisDevice)
        case .testCopy: show(TideSyncMessages.testCopy)
        case .live:
            if !hasAddress {
                show(TideSyncMessages.needsAddress)
            } else if !settings.isOn {
                show(TideSyncMessages.off)
            }
        }
    }

    fileprivate func show(_ message: String, details: [String] = [], problem: Bool = false) {
        statusMessage = message
        statusDetails = details.isEmpty ? nil : details.joined(separator: "\n")
        statusIsProblem = problem
    }
}
