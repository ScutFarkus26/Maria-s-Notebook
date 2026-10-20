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
    /// once the hold says to, or once its stack is no longer the open one.
    static let liveAttempt: Attempt = { ids, container, context in
        let attemptOn = ObjectIdentifier(container)
        return await CDAttendanceStore.attachNewRecordsToClassroomShare(
            ids, container: container, pinContext: context,
            stopReason: { @MainActor in
                AssistantShareAttacher.stopReason(
                    attemptOn: attemptOn,
                    open: AssistantStack.current.map { ObjectIdentifier($0.container) },
                    hold: AssistantStack.filingStopReason
                )
            }
        )
    }

    /// Why an attempt on the container `attemptOn` must stop before its next
    /// chunk: the filing hold's reason, or its stack having been closed or
    /// rebuilt since. A call let go of after the watchdog (`letGoOfStuckPass`)
    /// went on sending its later chunks to the closed stack's container
    /// (2026-10-20 review b, item 4).
    nonisolated static func stopReason(attemptOn: ObjectIdentifier, open: ObjectIdentifier?, hold: String?) -> String? {
        guard open == attemptOn else { return stackClosedReason }
        return hold
    }

    /// Why an attempt on a closed stack stops (logged).
    nonisolated static let stackClosedReason = "the class's stack was rebuilt or closed"

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
