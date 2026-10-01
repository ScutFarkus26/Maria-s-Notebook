import CloudKit
import Foundation
import Testing
@testable import CosmicDaybook

/// The release's waits on iCloud: a request that never answers, errors worth asking again
/// for, and knowing when the notebook's exports run.
@Suite("CloudKit server check and export activity")
struct CloudKitServerCheckTests {

    @Test("A request that never answers is abandoned after its limit")
    func hungRequestTimesOut() async {
        await #expect(throws: CloudKitServerCheck.TimedOut.self) {
            _ = try await CloudKitServerCheck.withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(30))
                return 1
            }
        }
        #expect(CloudKitServerCheck.isTransient(CloudKitServerCheck.TimedOut()))
        #expect(CloudKitServerCheck.isTransient(CKError(.networkUnavailable)))
        #expect(!CloudKitServerCheck.isTransient(CKError(.permissionFailure)))
    }

    @Test("The export watcher knows when exports run and when one started")
    func exportActivity() {
        let activity = ClassroomShareExportActivity(storeIdentifier: "store")
        let before = Date()
        #expect(activity.isIdle)
        #expect(!activity.startedAfter(before))
        let id = UUID()
        activity.record(id: id, start: before.addingTimeInterval(1), finished: false)
        #expect(!activity.isIdle)
        #expect(activity.startedAfter(before))
        activity.record(id: id, start: before.addingTimeInterval(1), finished: true)
        #expect(activity.isIdle)
    }
}
