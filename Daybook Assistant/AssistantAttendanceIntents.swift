import AppIntents
import CoreData

// The Assistant's own attendance commands, beside the shared here / late /
// absent / undo. Both read names aloud or change the whole class, so both
// need the phone unlocked.

// MARK: - Close arrival

/// The Late button by voice: everyone still unmarked is marked absent, and
/// from then on "Mark Maya here" marks tardy.
struct CloseArrivalIntent: AppIntent {
    static let title: LocalizedStringResource = "Close Arrival"
    static let description = IntentDescription(
        "Mark every child not yet marked absent, and switch to Late: a child who arrives after this is marked tardy.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try SiriAttendance()
        let late = AssistantAttendanceViewModel.LatePhaseMemory.self
        guard !late.isLate(on: session.today) else {
            return .result(dialog: "Arrival is already closed.")
        }
        guard !session.store.isLocked(session.today) else { throw SiriAttendanceError.dayLocked }
        guard session.isSchoolDay else {
            return .result(dialog: "Today isn't a school day, so there's no arrival to close.")
        }

        let (roll, unmarked) = try AssistantDayRoll.today(in: session)
        let waiting = unmarked.count
        if waiting > 0 {
            try await requestConfirmation(
                dialog: "Mark the \(waiting) \(waiting == 1 ? "child" : "children") not yet marked absent?"
            )
        }

        let changed = try session.store.markUnmarkedAbsent(for: session.today, students: roll)
        // Late before the commit, whose notification reloads an open grid.
        late.setLate(true, on: session.today)
        if changed.isEmpty {
            // Still remembered, so "Undo" reopens arrival rather than putting
            // back an earlier Siri mark.
            SiriAttendanceChange(day: session.today, marks: [], summary: "closing arrival", closedArrival: true)
                .remember()
            NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
            return .result(dialog: "Arrival is closed. Everyone was already marked.")
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
            late.setLate(false, on: session.today)
            throw error
        }
        let count = changed.count
        return .result(dialog: IntentDialog(
            full: "Arrival is closed. \(count) \(count == 1 ? "child is" : "children are") marked absent.",
            supporting: "\(count) absent"
        ))
    }
}

// MARK: - Who's missing

/// "Who's not here yet?": the children still unmarked today, by the names the
/// grid shows.
struct WhoIsMissingIntent: AppIntent {
    static let title: LocalizedStringResource = "Who's Not Marked"
    static let description = IntentDescription(
        "Hear which children aren't marked yet today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try SiriAttendance()
        guard session.isSchoolDay else {
            return .result(dialog: "Today isn't a school day.")
        }
        let (roll, missing) = try AssistantDayRoll.today(in: session)
        guard !missing.isEmpty else {
            return .result(dialog: "Everyone is marked.")
        }
        let names = AssistantAttendanceViewModel.gridNames(for: roll)
        let list = missing.map { names[$0.objectID] ?? $0.firstName }
            .formatted(.list(type: .and))
        let count = missing.count
        return .result(dialog: IntentDialog(
            full: "\(count) not marked yet: \(list).",
            supporting: "\(count) not marked"
        ))
    }
}
