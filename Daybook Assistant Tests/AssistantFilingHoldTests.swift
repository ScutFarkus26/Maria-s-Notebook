import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Siri's marks went to `share(_:to:)` on a classroom share store whose
// CloudKit setup had failed, which can crash the app: the attacher stopped
// only on a stop its own earlier attach had found (2026-10-10 review, #1).
// The store's own events now hold filing, and a pass waits while they do.
@Suite("Assistant filing hold")
@MainActor
struct AssistantFilingHoldTests {

    private func event(
        _ type: NSPersistentCloudKitContainer.EventType,
        succeeded: Bool,
        killedDelegate: Bool = false,
        at start: Date,
        store: String = "shared"
    ) -> AssistantFilingHold.Event {
        AssistantFilingHold.Event(
            type: type, succeeded: succeeded, killedDelegate: killedDelegate, start: start, storeIdentifier: store
        )
    }

    @Test("A failed setup holds filing until an import or export of that store that began later succeeds")
    func failedSetupHoldsUntilSynced() {
        let hold = AssistantFilingHold()
        let lifts = LiftCount()
        hold.onLift = { lifts.count += 1 }
        let failedAt = Date()
        #expect(hold.stopReason == nil)

        hold.follow(event(.setup, succeeded: false, at: failedAt))
        #expect(hold.stopReason == AssistantFilingHold.reason)
        hold.follow(event(.export, succeeded: true, at: failedAt.addingTimeInterval(-1)))
        hold.follow(event(.setup, succeeded: true, at: failedAt.addingTimeInterval(1)))
        hold.follow(event(.import, succeeded: true, at: failedAt.addingTimeInterval(1), store: "another"))
        #expect(hold.stopReason != nil, "began before, a setup alone, or another store")
        #expect(lifts.count == 0)

        hold.follow(event(.export, succeeded: true, at: failedAt.addingTimeInterval(1)))
        #expect(hold.stopReason == nil)
        #expect(lifts.count == 1, "what waits goes in at once")
    }

    @Test("A sync that says its delegate died holds; one that failed for another reason doesn't")
    func deadDelegateHolds() {
        let hold = AssistantFilingHold()
        let start = Date()
        hold.follow(event(.export, succeeded: false, at: start))
        #expect(hold.stopReason == nil, "an export that failed for the network retries by itself")
        hold.follow(event(.import, succeeded: false, killedDelegate: true, at: start))
        #expect(hold.stopReason != nil)
        hold.follow(event(.import, succeeded: true, at: start.addingTimeInterval(1)))
        #expect(hold.stopReason == nil)
    }

    @Test("While the share's store is held no pass tries a mark; once it lifts, the waiting marks go in")
    func heldStoreKeepsMarksWaiting() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let share = FakeShare()
        let gate = HoldGate()
        gate.reason = AssistantFilingHold.reason
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), sleep: share.sleep, attempt: share.attempt,
            filingStopReason: { gate.reason }
        )
        let records = (0..<2).map { _ in
            let record = CDAttendanceRecord(context: context)
            record.id = UUID()
            return record
        }
        #expect(context.safeSave())
        let saved = records.map(\.objectID)

        attacher.attach(saved, container: stack.container, context: context)
        await attacher.waitUntilIdle()
        #expect(share.attempts.isEmpty, "share(_:to:) on a store whose setup failed can crash the app")
        #expect(attacher.pending == saved.map { $0.uriRepresentation() })

        gate.reason = nil
        attacher.retryWaiting()
        await attacher.waitUntilIdle()
        #expect(share.attempts == [saved])
        #expect(attacher.pending.isEmpty)
    }
}

/// How many times a hold lifted.
@MainActor
private final class LiftCount {
    var count = 0
}

/// The hold as a test sets it.
@MainActor
private final class HoldGate {
    var reason: String?
}
