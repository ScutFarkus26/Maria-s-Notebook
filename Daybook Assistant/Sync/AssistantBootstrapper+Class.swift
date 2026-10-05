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
        case ignore, rebuild, giveUp
    }

    /// What a stop the share attacher reports calls for. Only a new
    /// container sends again, so the first stop on the open stack rebuilds
    /// it, as the iCloud account arriving does. A stop on a stack that's
    /// gone since, or while the app is starting, failed or leaving, is
    /// ignored. If the rebuilt stack stops too within
    /// `mirroringRebuildWindow` it isn't rebuilt again (that could go round
    /// for good): the sync line says to reopen the app. A stop long after,
    /// on a stack that worked meanwhile, gets its own rebuild.
    nonisolated static func mirroringStopResponse(
        onOpenStack: Bool, settled: Bool, rebuiltBefore: Bool
    ) -> MirroringStopResponse {
        guard onOpenStack, settled else { return .ignore }
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
        case .rebuild:
            rebuiltForMirroringStopAt = Date()
            Task { await rebuildStack(because: "CloudKit mirroring stopped") }
        case .giveUp:
            Self.classLogger.error("CloudKit mirroring stopped again on the rebuilt stack")
            sendingStopped = true
        }
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
