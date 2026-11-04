import Foundation
import CoreData

// How long the backlog rests after a failed pass, which waiting marks still
// exist to be tried, and the small reads of where a pass stands.

extension AssistantShareAttacher {

    /// Whether a pass is running now.
    var isRunning: Bool { pass != nil }

    /// A pass is running whose share call hasn't outlived the watchdog:
    /// what locking the phone keeps it awake for. A call past the watchdog
    /// may never come back, and counting it kept the phone awake for the
    /// full keep-alive on every lock (bug hunt 2026-11-03 #10).
    var isBusy: Bool { pass != nil && !sendingLooksStuck }

    /// Returns once no pass is running, or the running one's share call has
    /// outlived the watchdog: Siri keeps its launch alive this long, and so
    /// does locking the phone. A pass let go of for a rebuilt stack ends the
    /// wait for it, and the new pass is waited for instead. Waiting on the
    /// stuck pass's own end left a task suspended on it with every lock.
    func waitUntilIdle() async {
        while pass != nil, !sendingLooksStuck {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
    }

    /// Ends every `waitUntilIdle()` wait, which then looks again: the pass
    /// ended or was let go of, or its call outlived the watchdog.
    func wakeIdleWaiters() {
        let waiting = idleWaiters
        idleWaiters = []
        waiting.forEach { $0.resume() }
    }

    /// Marks wait with a chance of going: offline (the network may be back),
    /// or their rest is over. A mark resting after refusals waits it out.
    var waitingHaveAChance: Bool {
        pendingCount > 0 && (isOffline || now() >= backlogWaitsUntil)
    }

    /// `retryWaiting()`, only for marks with a chance (`waitingHaveAChance`):
    /// what locking the phone tries (bug hunt 2026-10-16 #3).
    func retryWaitingIfAChance() {
        guard waitingHaveAChance else { return }
        retryWaiting()
    }

    /// What waits, by kind, for Leave's warning: her attendance marks, and
    /// the other changes the guide would lose (Restock lines, front-desk
    /// sends). Her own name in the class's list isn't counted: leaving takes
    /// it off anyway. Every record used to count as a mark, so one mark and
    /// her name read "2 marks haven't reached your guide" (bug hunt
    /// 2026-11-02 #43).
    func waitingByKind() -> (marks: Int, otherChanges: Int) {
        let coordinator = lastContext?.persistentStoreCoordinator
        var marks = 0, otherChanges = 0
        for uri in pending {
            switch Self.entityName(of: uri, in: coordinator) {
            case "AttendanceRecord": marks += 1
            case "ClassroomPerson": break
            default: otherChanges += 1
            }
        }
        return (marks, otherChanges)
    }

    /// The entity a waiting record's URI names: from the store, or, with
    /// the store gone (a rebuilt stack), from the URI itself, which names it
    /// before the record's own number (`x-coredata://<store>/<Entity>/p<n>`).
    nonisolated static func entityName(of uri: URL, in coordinator: NSPersistentStoreCoordinator?) -> String? {
        if let id = coordinator?.managedObjectID(forURIRepresentation: uri) { return id.entity.name }
        let parts = uri.pathComponents
        return parts.count >= 2 ? parts[parts.count - 2] : nil
    }

    /// One minute after the first failed pass in a row, doubling each time
    /// after, and never more than ten.
    static func rest(afterFailures failures: Int) -> TimeInterval {
        min(60 * pow(2, Double(max(failures, 1) - 1)), 10 * 60)
    }

    /// After a pass that couldn't reach iCloud: 30 seconds, doubling, never
    /// more than two minutes. Retrying is cheap once the pass stops at the
    /// first network failure, and on Wi-Fi that's weak but never drops
    /// nothing else says the network is back. Other refusals: `rest(afterFailures:)`.
    static func rest(afterFailures failures: Int, noConnection: Bool) -> TimeInterval {
        guard noConnection else { return rest(afterFailures: failures) }
        return min(30 * pow(2, Double(max(failures, 1) - 1)), 2 * 60)
    }

    /// The waiting records that still exist (`ids`), and those that are
    /// gone for good (`gone`): deleted, or from a store this open stack
    /// doesn't have, which a Rebuild from iCloud replaced. A stack with no
    /// stores open (one closed for a rebuild) can say neither, so its
    /// marks are in neither list and keep waiting.
    func resolve(
        _ uris: [URL], in context: NSManagedObjectContext
    ) -> (ids: [NSManagedObjectID], gone: [URL]) {
        guard let coordinator = context.persistentStoreCoordinator,
              !coordinator.persistentStores.isEmpty else { return ([], []) }
        var ids: [NSManagedObjectID] = []
        var gone: [URL] = []
        for uri in uris {
            if let id = coordinator.managedObjectID(forURIRepresentation: uri),
               (try? context.existingObject(with: id)) != nil {
                ids.append(id)
            } else {
                gone.append(uri)
            }
        }
        return (ids, gone)
    }
}
