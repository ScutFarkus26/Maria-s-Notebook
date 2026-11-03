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

    @Test("A request that ignores cancellation is still abandoned at its limit")
    func uncancellableRequestTimesOut() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: CloudKitServerCheck.TimedOut.self) {
            _ = try await CloudKitServerCheck.withTimeout(.milliseconds(50)) {
                // A wait that never looks at cancellation, as reading the share's mirroring
                // metadata off the main actor doesn't.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                return 1
            }
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test("A zone that's gone is told apart from a record that's gone, and other failures throw")
    func zoneGoneIsNotRecordGone() throws {
        let zone = CKRecordZone.ID(zoneName: "share", ownerName: CKCurrentUserDefaultName)
        let held = CKRecord(recordType: "CD_Student", recordID: CKRecord.ID(recordName: "held", zoneID: zone))
        let deleted = CKRecord.ID(recordName: "deleted", zoneID: zone)
        let inGoneZone = CKRecord.ID(recordName: "zone-gone", zoneID: zone)
        let inUserDeletedZone = CKRecord.ID(recordName: "user-deleted", zoneID: zone)
        let answer = try CloudKitServerCheck.sorted([
            held.recordID: .success(held),
            deleted: .failure(CKError(.unknownItem)),
            inGoneZone: .failure(CKError(.zoneNotFound)),
            inUserDeletedZone: .failure(CKError(.userDeletedZone))
        ])
        #expect(Set(answer.found.keys) == [held.recordID])
        #expect(answer.inMissingZones == [inGoneZone, inUserDeletedZone])
        #expect(throws: CKError.self) {
            try CloudKitServerCheck.sorted([deleted: .failure(CKError(.permissionFailure))])
        }
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
