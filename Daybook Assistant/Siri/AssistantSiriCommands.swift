import CoreData

/// The work behind the Assistant's own Siri commands, apart from Siri's
/// confirmation and answers, so tests can run it on an in-memory stack
/// (`SiriAttendance(stack:role:today:)`) rather than the app's real one.
@MainActor
enum AssistantSiriCommands {

    enum CloseCheck: Equatable {
        case alreadyClosed
        case notSchoolDay
        /// Arrival can close; this many children would be marked absent.
        case ready(waiting: Int)
    }

    private typealias Late = AttendanceLatePhase

    /// What Siri says when today's roll is empty: the class's children
    /// haven't come down from iCloud yet (a fresh join, a rebuilt store).
    static let classNotLoadedMessage = "The class hasn't loaded on this iPhone yet. Try again in a moment."

    /// Whether arrival can close today, and how many it would mark. Throws
    /// `dayLocked` on a locked day, `viewOnly` while the guide has her as
    /// View only, and `notReady` when the roll is empty.
    ///
    /// The last two are the arrival bar's rules, which never offers Close
    /// Arrival then: Siri marked no one, said "Everyone was already
    /// marked" and still put the day into Late, so every child tapped in
    /// afterwards was marked late, at the front desk and in ParentLocker
    /// too, even once she could make changes again (bug hunt 2026-11-06, #1).
    static func checkClose(_ session: SiriAttendance) throws -> CloseCheck {
        try session.refuseIfViewOnly()
        let closedAnywhere = (try? session.store.arrivalClosed(on: session.today)) == true
        guard !Late.isLate(on: session.today, closedAnywhere: closedAnywhere) else { return .alreadyClosed }
        guard !session.store.isLocked(session.today) else { throw SiriAttendanceError.dayLocked }
        guard session.isSchoolDay else { return .notSchoolDay }
        let day = try AssistantDayRoll.today(in: session)
        guard !day.roll.isEmpty else { throw SiriAttendanceError.notReady(classNotLoadedMessage) }
        return .ready(waiting: day.unmarked.count)
    }

    /// Marks everyone still unmarked on today's roll absent and closes
    /// arrival. Returns how many it marked.
    ///
    /// Checked again here (`checkClose`): while Siri waits for her yes the
    /// day can be locked, and the store would mark no one, which read as
    /// "Everyone was already marked" and closed arrival anyway; or arrival
    /// can be closed on the grid, and this one was remembered as Siri's, so
    /// "Undo that" took back the grid's.
    ///
    /// Late is set only when the close marked someone, or when the roll
    /// really was all marked (after a Reopen Arrival, say): a close that
    /// marked no one with children still unmarked is refused, and arrival
    /// stays open (#1). A day reopened here before is remembered with the
    /// change, so its Undo reopens it again (#3).
    static func closeArrival(_ session: SiriAttendance) async throws -> Int {
        if try checkClose(session) == .alreadyClosed { throw SiriAttendanceError.arrivalAlreadyClosed }
        let roll = try AssistantDayRoll.today(in: session).roll
        let changed = try session.store.markUnmarkedAbsent(for: session.today, students: roll)
        guard try !changed.isEmpty || AssistantDayRoll.today(in: session).unmarked.isEmpty else {
            throw SiriAttendanceError.saveFailed
        }
        let reopened = Late.isReopened(on: session.today)
        // Late before the commit, whose notification reloads an open grid.
        Late.setLate(true, on: session.today)
        if changed.isEmpty {
            // Still remembered, so "Undo" reopens arrival rather than putting
            // back an earlier Siri mark.
            SiriAttendanceChange(
                day: session.today, marks: [], summary: "closing arrival", closedArrival: true,
                reopenedBefore: reopened
            ).remember()
            NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
            return 0
        }
        do {
            // With Close Arrival's marker, so "Undo" leaves a child given a
            // reason since ("Absent, Sick") as she is.
            try await session.commit(
                changed.map {
                    SiriAttendance.Pending(
                        record: $0, from: .unmarked, to: .absent,
                        toReasonRaw: AttendanceDeduplication.automaticAbsenceRaw
                    )
                },
                created: changed.filter(\.isInserted),
                summary: "closing arrival",
                closedArrival: true,
                reopenedBefore: reopened
            )
        } catch {
            // Nothing was saved (the commit put the marks back), so arrival
            // stays open and asking again tries again, reopened as it was.
            if reopened { Late.reopen(on: session.today) } else { Late.setLate(false, on: session.today) }
            throw error
        }
        return changed.count
    }

    /// The children on today's roll with no mark, by the names on their
    /// tiles; nil when today isn't a school day.
    static func missingNames(_ session: SiriAttendance) throws -> [String]? {
        guard session.isSchoolDay else { return nil }
        let day = try AssistantDayRoll.today(in: session)
        let names = AttendanceGridNames.names(for: day.roll)
        return day.unmarked.map { names[$0.objectID] ?? $0.firstName }
    }

    /// The children on today's roll marked absent, by the names on their
    /// tiles; nil when today isn't a school day.
    static func absentNames(_ session: SiriAttendance) throws -> [String]? {
        guard session.isSchoolDay else { return nil }
        let day = try AssistantDayRoll.today(in: session)
        let names = AttendanceGridNames.names(for: day.roll)
        return day.absent.map { names[$0.objectID] ?? $0.firstName }
    }
}
