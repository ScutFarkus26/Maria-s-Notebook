import Foundation
import CoreData
import OSLog

/// Coordinates post-sync deduplication with debouncing to prevent rapid-fire runs.
/// Triggered by CloudKit import events to clean up merge-conflict duplicates.
///
/// Two callers feed one debounced cycle. `PersistentHistoryProcessor` reports
/// which entities a remote batch inserted, and the pass is scoped to exactly
/// those (an empty report means nothing to sweep); when it cannot read history
/// it asks for the full sweep instead. `CloudKitSyncStatusService` reports each
/// successful import, which only arms the cycle: an import that wrote rows
/// always comes with a history report, so an import event with no report in
/// its cycle (CloudKit polled and found nothing) runs no pass. A plain
/// `requestDeduplication()` always sweeps everything.
@Observable
final class DeduplicationCoordinator {
    static let shared = DeduplicationCoordinator()
    nonisolated private static let logger = Logger.deduplicationCoordinator

    var persistentContainer: NSPersistentContainer?

    /// CoreDataStack reference used to run SharedStoreZoneRepair after
    /// each post-import dedup pass. Weak to avoid retain cycles —
    /// the stack owns this singleton's lifetime indirectly via AppDependencies.
    weak var coreDataStack: CoreDataStack?

    private var debounceTask: Task<Void, Never>?
    private var isRunning = false

    /// What the cycle now being debounced has been asked to read.
    private enum PendingScope {
        /// Only an import event has spoken (or nothing has): nothing was written.
        case unreported
        /// The history processor reported these inserted entities.
        case inserted(Set<String>)
        /// A plain request, or a report on top of one: sweep everything.
        case everything

        mutating func add(insertedEntities: Set<String>) {
            switch self {
            case .unreported: self = .inserted(insertedEntities)
            case let .inserted(names): self = .inserted(names.union(insertedEntities))
            case .everything: break
            }
        }

        /// `nil` when no history report arrived, so there is nothing to read.
        var resolved: DeduplicationScope? {
            switch self {
            case .unreported: return nil
            case .everything: return .everything
            case let .inserted(names): return DeduplicationScope(insertedEntities: names)
            }
        }
    }

    private var pendingScope: PendingScope = .unreported

    /// How long requests are coalesced before the pass runs. Fixed at 5 s in
    /// the app; the energy-gating tests shorten it so they don't sleep.
    private let debounceInterval: Duration

    /// Times the current debounce cycle found the device hot (or in Low Power
    /// Mode) and waited for it to cool instead of running. A pass never runs
    /// while the policy defers — it waits as long as that takes. Resets when
    /// a fresh request re-arms the cycle.
    private(set) var energyDeferralCount = 0

    /// How many times the debounced pass has been allowed to start. Bumped
    /// even when there is no container to work on, so it measures the gate
    /// rather than the outcome.
    private(set) var runAttemptCount = 0

    /// The scope the most recent cycle resolved to; `nil` when it ran no pass
    /// because no history report accompanied the import event.
    private(set) var lastRunScope: DeduplicationScope?

    /// How many cycles have fired, with or without a pass.
    private(set) var cycleCount = 0

    private init() {
        self.debounceInterval = .seconds(5)
    }

    /// Test seam: an isolated coordinator with a short debounce.
    init(debounceInterval: Duration) {
        self.debounceInterval = debounceInterval
    }

    /// Request a debounced deduplication run over every entity.
    /// Multiple calls within 5 seconds are coalesced into a single run.
    ///
    /// Deduplication is discretionary maintenance, so on a hot device or in
    /// Low Power Mode the debounced pass waits for the policy to clear (see
    /// `energyDeferralCount`); it never runs hot.
    func requestDeduplication(policy: EnergyPolicy = .shared) {
        pendingScope = .everything
        armDebounce(policy: policy)
    }

    /// The history processor's report: a remote batch inserted rows in these
    /// entities (possibly none). Reports within one cycle are unioned.
    func requestDeduplication(insertedEntities: Set<String>, policy: EnergyPolicy = .shared) {
        pendingScope.add(insertedEntities: insertedEntities)
        armDebounce(policy: policy)
    }

    /// A successful CloudKit import. Arms the cycle so a history report that
    /// lands beside it runs on time; alone it runs nothing, because an import
    /// that wrote rows always produces a report.
    func requestDeduplicationAfterImport(policy: EnergyPolicy = .shared) {
        armDebounce(policy: policy)
    }

    private func armDebounce(policy: EnergyPolicy) {
        debounceTask?.cancel()
        let interval = debounceInterval
        energyDeferralCount = 0
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            if policy.shouldDeferMaintenance {
                self?.energyDeferralCount += 1
                Self.logger.notice("Deduplication deferred until the device cools or Low Power Mode ends")
                // Suspends without polling; a newer request cancels this task
                // (and resumes the wait) before arming its own.
                await policy.waitUntilMaintenanceAllowed()
                guard !Task.isCancelled else { return }
            }
            self?.runDeduplication()
        }
    }

    private func runDeduplication() {
        cycleCount += 1
        let scope = pendingScope.resolved
        pendingScope = .unreported
        lastRunScope = scope
        guard let scope else {
            Self.logger.debug("Post-import deduplication skipped: the import wrote nothing")
            return
        }
        runAttemptCount += 1
        guard !isRunning, let container = persistentContainer else { return }
        isRunning = true

        // Nothing was inserted, so there is nothing to read: skip the context
        // and the pass, but still make the zone-repair call every pass ends with.
        guard !scope.isEmpty else {
            Self.logger.debug("Post-import deduplication skipped: the import inserted nothing")
            finishRun()
            return
        }

        let bgContext = container.newBackgroundContext()
        bgContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // Tagged like every other context the app writes through, so the
        // history processor recognises the pass's deletes as local. Untagged,
        // they read as a remote batch and re-armed this coordinator, the
        // zone-repair gate and the entity notifications after every pass;
        // `sweep` now posts those notifications itself.
        bgContext.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        // CloudKit container for deterministic survivor selection — every device
        // must keep the same duplicate, or peers delete each other's survivors.
        let cloudKitContainer = container as? NSPersistentCloudKitContainer

        Task.detached(priority: .utility) { [weak self] in
            await bgContext.perform {
                Self.sweep(scope, in: bgContext, container: cloudKitContainer)
            }
            await MainActor.run { [weak self] in
                self?.finishRun()
            }
        }
    }

    /// One pass on the background context's queue: dedup, save if anything
    /// folded, and log how long it took.
    nonisolated private static func sweep(
        _ scope: DeduplicationScope,
        in context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) {
        let start = Date()
        // Some merges save part-way through, so collect what every save of
        // the pass wrote rather than only the final one.
        let saved = SavedEntityNames(observing: context)
        let results = DataCleanupService.deduplicateAllModels(using: context, container: container, scope: scope)
        if !results.isEmpty, context.safeSave() {
            let removed: Int = results.values.reduce(0, +)
            logger.info("Post-import deduplication removed \(removed) duplicates")
        }
        // What the history processor used to post for these saves while the
        // context was untagged: the school-day cache and the presentation
        // screens hear about the folded rows as before.
        PersistentHistoryProcessor.postEntityNotifications(for: saved.finish())
        let elapsed: String = String(format: "%.2f", Date().timeIntervalSince(start))
        let scoped: String = describe(scope)
        logger.debug("Post-import deduplication (\(scoped, privacy: .public)) took \(elapsed, privacy: .public)s")
    }

    nonisolated private static func describe(_ scope: DeduplicationScope) -> String {
        guard let names = scope.entityNames else { return "every entity" }
        return "\(names.count) entities"
    }

    private func finishRun() {
        isRunning = false
        if let stack = coreDataStack {
            // `runIfNeeded` honors the 24-hour circuit breaker that exists
            // to stop repeated full-database zone scans (each of which can
            // sit on a 10-minute CloudKit lock wait). Every other automatic
            // call site uses it; this one bypassed it on every import.
            Task { await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack) }
        }
    }
}

/// Collects the entity names of everything one context saves between
/// `init` and `finish()` — the entities those saves' history transactions
/// name. The did-save notification is posted synchronously on the saving
/// context's queue, which is the only queue that touches `names`.
nonisolated final class SavedEntityNames: @unchecked Sendable {
    private var names: Set<String> = []
    private var token: (any NSObjectProtocol)?

    init(observing context: NSManagedObjectContext) {
        token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil
        ) { [weak self] note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
            for key in keys {
                for object in (note.userInfo?[key] as? Set<NSManagedObject>) ?? [] {
                    if let name = object.objectID.entity.name { self?.names.insert(name) }
                }
            }
        }
    }

    /// Stops observing and returns what was saved.
    func finish() -> Set<String> {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        return names
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
