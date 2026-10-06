import Foundation
import CoreData
import CloudKit
import OSLog

// Keeping the class reachable: CloudKit mirroring stopping, marks not yet
// sent when she leaves, being taken out of the class, and the stores'
// history.

extension AssistantBootstrapper {

    private static let classLogger = Logger.app(category: "bootstrap")

    /// True inside a hosted `Daybook Assistant Tests` run, the same check as
    /// the notebook's `AppBootstrapping.isRunningUnitTests`.
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The guide's name as the share's owner identity gives it, for display
    /// only (Apple's terms: never stored). Nil when CloudKit withholds it.
    var guideName: String? {
        let name = sharingService?.currentShare?.owner.userIdentity.nameComponents?.formatted().trimmed() ?? ""
        return name.isEmpty ? nil : name
    }

    /// The guide's name as her screens show it: the one he set in the
    /// classroom's list (`ClassroomNames`), then Apple's (`guideName`). Nil
    /// without either.
    var guideNameToShow: String? {
        coreDataStack.flatMap { ClassroomNames.guideName(in: $0.viewContext) } ?? guideName
    }

    /// An import that finds no membership row means she left on another
    /// iPhone, unless the Leave is this iPhone's own and still running.
    nonisolated static func leftElsewhere(hasOwnRow: Bool, leavingHere: Bool) -> Bool {
        !hasOwnRow && !leavingHere
    }

    // MARK: - CloudKit mirroring stopped

    enum MirroringStopResponse: Equatable {
        case ignore, later, rebuild, giveUp
    }

    /// What a stop the share attacher reports calls for. Only a new
    /// container sends again, so the first stop on the open stack rebuilds
    /// it, as the iCloud account arriving does. A stop on a stack that's
    /// gone since is ignored. One on the open stack while the app is
    /// starting, failed or leaving waits until it isn't
    /// (`settleDeferredStop`): dropped, the marks stalled with nothing said
    /// until a relaunch. If the rebuilt stack stops too within
    /// `mirroringRebuildWindow` it isn't rebuilt again (that could go round
    /// for good): the sync line says to reopen the app. A stop long after,
    /// on a stack that worked meanwhile, gets its own rebuild.
    nonisolated static func mirroringStopResponse(
        onOpenStack: Bool, settled: Bool, rebuiltBefore: Bool
    ) -> MirroringStopResponse {
        guard onOpenStack else { return .ignore }
        guard settled else { return .later }
        return rebuiltBefore ? .giveUp : .rebuild
    }

    /// A stop this soon after the last rebuild counts as the rebuilt stack
    /// stopping too.
    nonisolated static let mirroringRebuildWindow: TimeInterval = 10 * 60

    private var rebuiltForMirroringStopRecently: Bool {
        guard let last = rebuiltForMirroringStopAt else { return false }
        return Date().timeIntervalSince(last) < Self.mirroringRebuildWindow
    }

    func observeMirroringStops() {
        AssistantShareAttacher.shared.onMirroringStopped = { [weak self] container in
            self?.mirroringStopped(in: container)
        }
    }

    func mirroringStopped(in container: NSPersistentCloudKitContainer) {
        let settled = switch phase {
        case .ready, .needsClassroom: !isLeavingHere
        case .starting, .failed: false
        }
        switch Self.mirroringStopResponse(
            onOpenStack: AssistantStack.current?.container === container,
            settled: settled,
            rebuiltBefore: rebuiltForMirroringStopRecently
        ) {
        case .ignore:
            break
        case .later:
            deferredStop = container
        case .rebuild:
            rebuiltForMirroringStopAt = Date()
            Task { await rebuildStack(because: "CloudKit mirroring stopped") }
        case .giveUp:
            Self.classLogger.error("CloudKit mirroring stopped again on the rebuilt stack")
            sendingStopped = true
        }
    }

    /// A stop held back while the app was starting, failed or leaving, now
    /// that it may not be: at the end of each membership read, opening the
    /// sample and Leave. Still unsettled, it waits again; a stack rebuilt
    /// meanwhile makes it moot.
    func settleDeferredStop() {
        guard let container = deferredStop else { return }
        deferredStop = nil
        mirroringStopped(in: container)
    }

    // MARK: - Rebuilding the stack

    /// Before a rebuild takes the stores off: a running attach finishes on
    /// the old stack (one cut off read "no shared store" and dropped its
    /// marks), up to a limit, since a `share(_:to:)` can hang. At least as
    /// long as the screens had before to let go of the old stack's objects.
    func waitForAttachBeforeRebuild(_ attacher: AssistantShareAttacher) async {
        let started = ContinuousClock.now
        if !(await attacher.waitUntilIdle(upTo: .seconds(10))) {
            Self.classLogger.notice("An attach still running; rebuilding anyway, its marks stay waiting")
        }
        let grace = Duration.milliseconds(300) - (ContinuousClock.now - started)
        if grace > .zero { try? await Task.sleep(for: grace) }
    }

    // MARK: - Leaving with marks not sent

    /// Marks this iPhone holds that haven't reached the guide: some waiting
    /// to go into the share (counted), or a save iCloud hasn't sent yet.
    enum UnsentMarks: Equatable {
        case counted(Int)
        case uncounted

        var message: String {
            let what = switch self {
            case .counted(1): "1 mark hasn't reached your guide yet."
            case .counted(let count): "\(count) marks haven't reached your guide yet."
            case .uncounted: "Your latest marks haven't reached your guide yet."
            }
            return what + " If you leave now, they're lost. Wait tries to send them first."
        }
    }

    nonisolated static func unsentMarks(waitingForShare: Int, unsentSave: Bool) -> UnsentMarks? {
        if waitingForShare > 0 { return .counted(waitingForShare) }
        return unsentSave ? .uncounted : nil
    }

    /// What Leave would lose now. Leave purges the class at once, so marks
    /// still on their way never reached the guide.
    func unsentMarks() -> UnsentMarks? {
        Self.unsentMarks(
            waitingForShare: AssistantShareAttacher.shared.pending.count,
            unsentSave: AssistantStack.keepAlive?.hasUnsentWork ?? false
        )
    }

    /// Leave's Wait: tries the waiting marks now and gives them up to
    /// `limit` to go. Returns what's still unsent.
    func sendUnsentMarks(upTo limit: Duration = .seconds(25)) async -> UnsentMarks? {
        let deadline = ContinuousClock.now + limit
        AssistantShareAttacher.shared.retryWaiting()
        while AssistantShareAttacher.shared.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        await AssistantStack.keepAlive?.waitUntilSent(upTo: max(.zero, deadline - ContinuousClock.now))
        return unsentMarks()
    }

    /// How long Leave waits for a running attach before saying to try again.
    nonisolated static let leaveWaitLimit: Duration = .seconds(20)

    /// Once the class is off this iPhone: the marks that were still waiting
    /// to go into its share are given up. The purge takes only the class's
    /// share zone, and these were never in it, so they stayed in the shared
    /// store and went into whichever class she joined next. Deleted only
    /// where CloudKit confirms they're in no share
    /// (`CDAttendanceStore.deleteUnsharedRecords`): one in a share is the
    /// guide's, and its delete would reach him. Call it with the attacher
    /// held and idle.
    func giveUpWaitingMarks(_ waiting: [URL]) async {
        if let stack = AssistantStack.current, let sharedStore = stack.sharedPersistentStore, !waiting.isEmpty {
            let coordinator = stack.container.persistentStoreCoordinator
            let ids = waiting.compactMap { coordinator.managedObjectID(forURIRepresentation: $0) }
                .filter { $0.persistentStore === sharedStore }
            do {
                let deleted = try await CDAttendanceStore.deleteUnsharedRecords(ids, container: stack.container)
                Self.classLogger.notice("Leave deleted \(deleted, privacy: .public) mark(s) the guide never had")
            } catch {
                let detail = error.localizedDescription
                Self.classLogger.error("Couldn't tell which waiting marks were shared: \(detail, privacy: .public)")
                Self.leaveBehind(waiting)
            }
        } else {
            Self.leaveBehind(waiting)
        }
        AssistantShareAttacher.shared.forgetWaiting()
        AssistantStack.keepAlive?.forgetUnsent()
    }

    // MARK: - Marks left behind

    /// Waiting marks Leave couldn't sort: CloudKit couldn't say which were
    /// already shared, or the running attach never finished. Forgotten, they
    /// stayed in the shared store, unfiled and on no list, and could go into
    /// the next class she joined. They're kept apart from the attach list (so
    /// they never go into a share) and deleted once CloudKit can say which are
    /// in no share, at the next launch or join (`deleteLeftBehindMarks`).
    nonisolated static var leftBehindKey: String { CloudKitEnvironment.scoped("Assistant.leftBehindMarks") }

    nonisolated static func leaveBehind(_ uris: [URL], defaults: UserDefaults = .standard) {
        guard !uris.isEmpty else { return }
        let known = defaults.stringArray(forKey: leftBehindKey) ?? []
        let added = uris.map(\.absoluteString).filter { !known.contains($0) }
        defaults.set(Array((known + added).suffix(500)), forKey: leftBehindKey)
    }

    private static var deletingLeftBehind = false

    /// Deletes the marks Leave left behind that are in no share; a mark in a
    /// share is the guide's and stays. Kept for the next try while CloudKit
    /// can't say.
    func deleteLeftBehindMarks(defaults: UserDefaults = .standard) async {
        let uris = (defaults.stringArray(forKey: Self.leftBehindKey) ?? []).compactMap(URL.init(string:))
        guard !uris.isEmpty, !Self.deletingLeftBehind, let stack = AssistantStack.current,
              let sharedStore = stack.sharedPersistentStore else { return }
        Self.deletingLeftBehind = true
        defer { Self.deletingLeftBehind = false }
        let coordinator = stack.container.persistentStoreCoordinator
        let ids = uris.compactMap { coordinator.managedObjectID(forURIRepresentation: $0) }
            .filter { $0.persistentStore === sharedStore }
        do {
            let deleted = try await CDAttendanceStore.deleteUnsharedRecords(ids, container: stack.container)
            defaults.removeObject(forKey: Self.leftBehindKey)
            Self.classLogger.notice("Deleted \(deleted, privacy: .public) mark(s) left behind by Leave")
        } catch {
            let detail = error.localizedDescription
            Self.classLogger.error("Marks left behind by Leave wait for the next try: \(detail, privacy: .public)")
        }
    }

    /// Leave on another of her iPhones: the same, once the running attach
    /// has finished (if it hasn't by the limit, the marks are only
    /// forgotten).
    func dropWaitingMarks() async {
        let attacher = AssistantShareAttacher.shared
        attacher.hold()
        defer { attacher.release() }
        if await attacher.waitUntilIdle(upTo: Self.leaveWaitLimit) {
            await giveUpWaitingMarks(attacher.pending)
        } else {
            Self.leaveBehind(attacher.pending)
            attacher.forgetWaiting()
            AssistantStack.keepAlive?.forgetUnsent()
        }
    }

    // MARK: - Taken out of the class

    /// The guide removed her from the share (or stopped sharing): the pinned
    /// share, once seen here, is gone from the shared store, and CloudKit
    /// took the class off with it, though the membership row stays. The
    /// phone stayed "joined" to an empty class that read "No students yet…
    /// a minute after you join". A share that can't be read while the class
    /// is still here (CloudKit not set up yet, 2026-09-29) isn't a removal.
    nonisolated static func removedFromClass(
        pinnedShareFound: Bool, sawPinnedShareBefore: Bool, classOnDevice: Bool
    ) -> Bool {
        !pinnedShareFound && sawPinnedShareBefore && !classOnDevice
    }

    /// Reads the shared store's shares off the main actor, one read at a
    /// time: an import burst asks for one more read, not one each.
    func checkStillInClass() {
        guard classCheck == nil else {
            classCheckAgain = true
            return
        }
        classCheck = Task { [weak self] in
            repeat {
                self?.classCheckAgain = false
                await self?.readClassShare()
            } while self?.classCheckAgain == true
            self?.classCheck = nil
        }
    }

    private func readClassShare() async {
        guard case .ready = phase, !AssistantSampleClass.isChosen,
              let stack = coreDataStack,
              let storeID = stack.sharedPersistentStore?.identifier,
              let zone = CDClassroomMembership.pinnedZoneName(in: stack.viewContext) else {
            removedFromClass = false
            return
        }
        let shares: [CKShare]
        do {
            shares = try await ClassroomShareAttach.shares(inStoreWithIdentifier: storeID, container: stack.container)
        } catch {
            // Couldn't tell: the last read stands.
            Self.classLogger.error("Reading the class's share failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard stack === coreDataStack, let sharedStore = stack.sharedPersistentStore else { return }
        let found = shares.contains { $0.recordID.zoneID.zoneName == zone }
        if found { AssistantClassroomLocalState.noteShareSeen(inZone: zone) }
        let removed = Self.removedFromClass(
            pinnedShareFound: found,
            sawPinnedShareBefore: AssistantClassroomLocalState.sawShare(inZone: zone),
            classOnDevice: !found && ClassroomSharingService.holdsClassroom(sharedStore, in: stack.viewContext)
        )
        if removed, !removedFromClass { Self.classLogger.notice("The class's share is gone; taken out of the class") }
        if removed != removedFromClass { removedFromClass = removed }
    }

    // MARK: - History

    /// Records each store's export starts from launch, and trims the
    /// stores' history once a launch, after the first screen
    /// (`AssistantHistoryTrim`).
    func startHistoryUpkeep() {
        guard exportRecorder == nil else { return }
        exportRecorder = AssistantHistoryTrim.recordExports()
        guard !historyTrimmed else { return }
        historyTrimmed = true
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard let container = AssistantStack.current?.container else { return }
            await AssistantHistoryTrim.trim(container)
        }
    }
}

/// Why Leave didn't start, said on the Classroom screen.
enum AssistantLeaveError: LocalizedError {
    /// Her marks were still going into the class's share when she tapped
    /// Leave, and still were after `leaveWaitLimit`.
    case stillSending

    var errorDescription: String? {
        switch self {
        case .stillSending:
            "Your marks are still on their way to your guide, so nothing was removed. Try Leave again in a minute."
        }
    }
}
