import Foundation
import CoreData
import OSLog

// The classroom share store's own health. A pass used to stop only on a stop
// its own earlier attach had found, so Siri's marks went to `share(_:to:)` on
// a store whose CloudKit setup had just failed, which can crash the app
// (2026-10-10 review, #1). Now each pass asks `AssistantFilingHold` first,
// and the real attempt asks it again before each chunk it sends. The marks
// wait, and go in once the store syncs again (`AssistantFilingHold.onLift`)
// or on a rebuilt stack.

extension AssistantShareAttacher {
    private static let holdLogger = Logger.app(category: "shareAttach")

    /// Why nothing may go into the share now, from the classroom share
    /// store's own CloudKit events (`AssistantFilingHold`), or nil.
    typealias FilingStopReason = @MainActor () -> String?

    /// The real attempt: `CDAttendanceStore`'s, stopping before any chunk
    /// once the hold says to.
    static let liveAttempt: Attempt = { ids, container, context in
        await CDAttendanceStore.attachNewRecordsToClassroomShare(
            ids, container: container, pinContext: context,
            stopReason: { @MainActor in AssistantStack.filingStopReason }
        )
    }

    /// The real zone check (`outsidePinnedZone`).
    static let liveZoneCheck: ZoneCheck = { ids, container, context in
        await AssistantShareAttacher.outsidePinnedZone(ids, container: container, context: context)
    }

    /// Whether a pass must wait for the classroom share's store, logged.
    func filingWaits() -> Bool {
        guard let reason = filingStopReason() else { return false }
        Self.holdLogger.notice("\(self.pending.count, privacy: .public) mark(s) wait: \(reason, privacy: .public)")
        return true
    }
}
