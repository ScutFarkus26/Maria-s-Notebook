import Foundation
import CoreData

// How long the backlog rests after a failed pass, which waiting marks still
// exist to be tried, and the small reads of where a pass stands.

extension AssistantShareAttacher {

    /// Whether a pass is running now.
    var isRunning: Bool { pass != nil }

    /// Returns once no pass is running: Siri keeps its launch alive this long.
    func waitUntilIdle() async {
        while let pass { await pass.value }
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
