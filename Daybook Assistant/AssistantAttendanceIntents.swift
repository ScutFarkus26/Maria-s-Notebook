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

        let roster = SiriHost.roster(in: session.context)
        let waiting = try unmarked(in: roster, session: session).count
        if waiting > 0 {
            try await requestConfirmation(
                dialog: "Mark the \(waiting) \(waiting == 1 ? "child" : "children") not yet marked absent?"
            )
        }

        let changed = try session.store.markUnmarkedAbsent(for: session.today, students: roster)
        late.setLate(true, on: session.today)
        if changed.isEmpty {
            NotificationCenter.default.post(name: .attendanceChangedBySiri, object: nil)
            return .result(dialog: "Arrival is closed. Everyone was already marked.")
        }
        try await session.commit(
            changed.map { SiriAttendance.Pending(record: $0, from: .unmarked, to: .absent) },
            created: changed.filter(\.isInserted),
            summary: "closing arrival",
            closedArrival: true
        )
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
        let roster = SiriHost.roster(in: session.context)
        let missing = try unmarked(in: roster, session: session)
        guard !missing.isEmpty else {
            return .result(dialog: "Everyone is marked.")
        }
        let names = AssistantAttendanceViewModel.gridNames(for: roster)
        let list = missing.map { names[$0.objectID] ?? $0.firstName }
            .formatted(.list(type: .and))
        let count = missing.count
        return .result(dialog: IntentDialog(
            full: "\(count) not marked yet: \(list).",
            supporting: "\(count) not marked"
        ))
    }
}

// MARK: - Shared

/// The children on `roster` with no mark today.
@MainActor
private func unmarked(in roster: [CDStudent], session: SiriAttendance) throws -> [CDStudent] {
    let marked = Set(
        try session.store.loadRecords(for: session.today)
            .deduplicatedPerStudentDay()
            .filter { $0.status != .unmarked }
            .map(\.studentID)
    )
    return roster.filter { !marked.contains($0.id?.uuidString ?? "") }
}
