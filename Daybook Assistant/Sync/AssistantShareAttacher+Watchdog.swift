import Foundation
import CoreData
import OSLog

// `share(_:to:)` has no time limit, and cancelling the task around it doesn't
// stop it (the Objective-C completion handler's bridge). One call that never
// came back held every later mark until she quit the app, while the line
// said "Sending to iCloud…", and a stack rebuilt meanwhile still waited on
// the old pass (bug hunt 2026-10-20 #7). The watchdog can't stop the call; it
// stops waiting for it.

extension AssistantShareAttacher {
    private static let watchdogLogger = Logger.app(category: "shareAttach")

    /// `attemptAndConfirm` raced against `watchdogLimit`. Nil when the pass
    /// was let go of before the call came back: its results are dropped.
    func attemptWatched(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext,
        token: Int
    ) async -> CDAttendanceStore.ShareAttachResult? {
        let timer = Task { [weak self, watchdog] in
            do { try await watchdog(Self.watchdogLimit) } catch { return }
            guard !Task.isCancelled else { return }
            self?.callOutlivedWatchdog(token: token, on: container)
        }
        let result = await attemptAndConfirm(ids, container: container, context: context)
        timer.cancel()
        guard token == passToken else {
            Self.watchdogLogger.notice("A share call let go of after the watchdog came back; its result is dropped")
            return nil
        }
        if sendingLooksStuck {
            sendingLooksStuck = false
            stuckContainer = nil
            Self.watchdogLogger.notice("A share call that outlived the watchdog came back")
        }
        return result
    }

    /// The pass's share call is still running at the limit: the line says
    /// so, and a stack rebuilt since no longer waits for it.
    func callOutlivedWatchdog(token: Int, on container: NSPersistentCloudKitContainer) {
        guard token == passToken, pass != nil else { return }
        let limit = Int(Self.watchdogLimit)
        Self.watchdogLogger.error("A share call has run \(limit, privacy: .public) s and may never return")
        sendingLooksStuck = true
        stuckContainer = container
        guard letGoOfStuckPass(), let lastContainer, let lastContext else { return }
        flush(container: lastContainer, context: lastContext)
    }

    /// Lets go of a pass whose share call outlived the watchdog on a stack
    /// that has since been rebuilt (or let go of), so a new pass can start
    /// on the new one. The old call may still finish: the token makes it
    /// exit with its results dropped, and the marks it was trying, still on
    /// the list, go again on the new stack, where anything it did put in is
    /// skipped as already shared (`ClassroomShareAttach.attach`). Returns
    /// whether it let one go.
    @discardableResult
    func letGoOfStuckPass() -> Bool {
        guard pass != nil, sendingLooksStuck, stuckContainer !== lastContainer else { return false }
        Self.watchdogLogger.notice("A rebuilt stack stops waiting for the stuck share call; a new pass starts")
        passToken += 1
        pass = nil
        sendingLooksStuck = false
        stuckContainer = nil
        return true
    }
}
