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

    /// Whether arrival can close today, and how many it would mark. Throws
    /// `dayLocked` on a locked day.
    static func checkClose(_ session: SiriAttendance) throws -> CloseCheck {
        guard !Late.isLate(on: session.today) else { return .alreadyClosed }
        guard !session.store.isLocked(session.today) else { throw SiriAttendanceError.dayLocked }
        guard session.isSchoolDay else { return .notSchoolDay }
        return .ready(waiting: try AssistantDayRoll.today(in: session).unmarked.count)
    }

    /// Marks everyone still unmarked on today's roll absent and closes
    /// arrival. Returns how many it marked.
    static func closeArrival(_ session: SiriAttendance) async throws -> Int {
        let roll = try AssistantDayRoll.today(in: session).roll
        let changed = try session.store.markUnmarkedAbsent(for: session.today, students: roll)
        // Late before the commit, whose notification reloads an open grid.
        Late.setLate(true, on: session.today)
        if changed.isEmpty {
            // Still remembered, so "Undo" reopens arrival rather than putting
            // back an earlier Siri mark.
            SiriAttendanceChange(day: session.today, marks: [], summary: "closing arrival", closedArrival: true)
                .remember()
            NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
            return 0
        }
        do {
            try await session.commit(
                changed.map { SiriAttendance.Pending(record: $0, from: .unmarked, to: .absent) },
                created: changed.filter(\.isInserted),
                summary: "closing arrival",
                closedArrival: true
            )
        } catch {
            // Nothing was saved (the commit put the marks back), so arrival
            // stays open and asking again tries again.
            Late.setLate(false, on: session.today)
            throw error
        }
        return changed.count
    }

    /// The children on today's roll with no mark, by the names on their
    /// tiles; nil when today isn't a school day.
    static func missingNames(_ session: SiriAttendance) throws -> [String]? {
        guard session.isSchoolDay else { return nil }
        let (roll, missing) = try AssistantDayRoll.today(in: session)
        let names = AttendanceGridNames.names(for: roll)
        return missing.map { names[$0.objectID] ?? $0.firstName }
    }
}
