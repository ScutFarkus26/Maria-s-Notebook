import Foundation
import Testing
@testable import Maria_s_Notebook

/// Boundary tests for `WatchListBuilder`, the rule that merges flagged notes,
/// "Watch…" todos and open goals into one per-child list.
///
/// Every case pins an explicit "today" (Wednesday 10 June 2026) and feeds the
/// pure value inputs, so nothing here depends on the clock or Core Data.
@Suite("WatchList Builder")
struct WatchListBuilderTests {

    // MARK: - Fixtures

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth, hour: hour)
        return AppCalendar.shared.date(from: components)!
    }

    /// Wednesday 10 June 2026.
    private var today: Date { day(2026, 6, 10) }

    private let alice = UUID()
    private let ben = UUID()

    private func note(
        _ body: String = "Kept restarting the stamp game.",
        students: [UUID]?,
        flagged: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> WatchNoteInput {
        WatchNoteInput(
            id: UUID(), needsFollowUp: flagged, studentIDs: students, body: body,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private func todo(
        _ title: String,
        students: [UUID],
        completed: Bool = false,
        someday: Bool = false,
        createdAt: Date? = nil,
        dueDate: Date? = nil
    ) -> WatchTodoInput {
        WatchTodoInput(
            id: UUID(), title: title, studentIDs: students, isCompleted: completed,
            isSomeday: someday, createdAt: createdAt, dueDate: dueDate
        )
    }

    private func goal(
        _ text: String = "Finish racks and tubes",
        student: UUID,
        active: Bool = true,
        createdAt: Date? = nil
    ) -> WatchGoalInput {
        WatchGoalInput(id: UUID(), studentID: student, text: text, isActive: active, createdAt: createdAt)
    }

    private func build(
        notes: [WatchNoteInput] = [], todos: [WatchTodoInput] = [], goals: [WatchGoalInput] = []
    ) -> [WatchItem] {
        WatchListBuilder.build(notes: notes, todos: todos, goals: goals)
    }

    // MARK: - 1. What counts as a Watch todo

    @Test("A title that starts with the word watch, in any case, is a Watch todo")
    func watchTodoTitles() {
        #expect(WatchListBuilder.isWatchTodo(title: "Watch Etty on the stamp game"))
        #expect(WatchListBuilder.isWatchTodo(title: "watch:"))
        #expect(WatchListBuilder.isWatchTodo(title: "  Watching Ora"))
        #expect(WatchListBuilder.isWatchTodo(title: "WATCH"))
        #expect(!WatchListBuilder.isWatchTodo(title: "Rewatch"))
        #expect(!WatchListBuilder.isWatchTodo(title: "Water the plants"))
        #expect(!WatchListBuilder.isWatchTodo(title: ""))
    }

    // MARK: - 2. Todo rows

    @Test("A Watch todo yields one row per linked child, carrying its due date")
    func watchTodoFansOutPerChild() {
        let due: Date = day(2026, 6, 12)
        let items: [WatchItem] = build(todos: [todo("Watch the checkerboard", students: [alice, ben], dueDate: due)])
        let expected: Set<UUID> = [alice, ben]
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2)
        #expect(Set(items.compactMap(\.studentID)) == expected)
        #expect(items.allSatisfy { $0.kind == .watchTodo && $0.dueDate == due })
    }

    @Test("Todos with no child, completed, someday, or not about watching yield nothing")
    func todosThatAreNotWatchRows() {
        let items = build(todos: [
            todo("Watch the class during transitions", students: []),
            todo("Watch Ben", students: [ben], completed: true),
            todo("Watch Ben", students: [ben], someday: true),
            todo("Call Ben's mother", students: [ben])
        ])
        #expect(items.isEmpty)
    }

    // MARK: - 3. Note rows

    @Test("A whole-class flagged note is one row with no child")
    func wholeClassNoteIsOneRow() {
        let items = build(notes: [note(students: nil)])
        #expect(items.count == 1)
        #expect(items.first?.studentID == nil)
        #expect(items.first?.kind == .flaggedNote)
    }

    @Test("A note naming two children is two rows; an unflagged note is none")
    func scopedNotesFanOut() {
        let items = build(notes: [
            note(students: [alice, ben]),
            note(students: [alice], flagged: false)
        ])
        let expected: Set<UUID> = [alice, ben]
        #expect(items.count == 2)
        #expect(Set(items.compactMap(\.studentID)) == expected)
    }

    @Test("A child's list excludes whole-class rows")
    func itemsForChildExcludeWholeClass() {
        let all = build(notes: [note(students: nil), note(students: [alice])])
        let mine = WatchListBuilder.items(for: alice, in: all)
        #expect(mine.count == 1)
        #expect(mine.first?.studentID == alice)
        #expect(WatchListBuilder.items(for: ben, in: all).isEmpty)
    }

    @Test("Row text is trimmed and capped at 200 characters")
    func textIsTrimmedAndCapped() {
        let long: String = String(repeating: "a", count: 250)
        let capped: String = String(repeating: "a", count: 200)
        let items: [WatchItem] = build(notes: [note("  \(long)  \n", students: [alice])])
        #expect(items.first?.text.count == 200)
        #expect(items.first?.text == capped)
    }

    // MARK: - 4. Goals

    @Test("Only active goals become rows, newest first")
    func activeGoalsOnly() {
        let items = build(goals: [
            goal("Older", student: alice, createdAt: day(2026, 6, 1)),
            goal("Dropped", student: alice, active: false, createdAt: day(2026, 6, 9)),
            goal("Newer", student: alice, createdAt: day(2026, 6, 8))
        ])
        #expect(items.map(\.text) == ["Newer", "Older"])
        #expect(items.allSatisfy { $0.kind == .goal })
    }

    // MARK: - 5. Identity

    @Test("Ids are unique across kinds and across children sharing a note")
    func identity() {
        let shared: WatchNoteInput = note(students: [alice, ben])
        let items: [WatchItem] = build(
            notes: [shared],
            todos: [todo("Watch Alice", students: [alice])],
            goals: [goal(student: alice)]
        )
        #expect(items.count == 4)
        #expect(Set(items.map(\.id)).count == 4)
        let noteRows: [WatchItem] = items.filter { $0.sourceID == shared.id }
        #expect(noteRows.count == 2)
        #expect(noteRows[0].id != noteRows[1].id)

        let once: [WatchItem] = build(notes: [shared])
        let again: [WatchItem] = build(notes: [shared])
        #expect(once == again)
    }

    // MARK: - 6. Dates

    @Test("A note's date is the later of updated and created; todos and goals use created")
    func rowDates() {
        let created = day(2026, 6, 1)
        let updated = day(2026, 6, 9)
        let items = build(
            notes: [note(students: [alice], createdAt: created, updatedAt: updated)],
            todos: [todo("Watch Alice", students: [alice], createdAt: created, dueDate: day(2026, 6, 11))],
            goals: [goal(student: alice, createdAt: day(2026, 6, 5))]
        )
        #expect(items.first { $0.kind == .flaggedNote }?.date == updated)
        #expect(items.first { $0.kind == .watchTodo }?.date == created)
        #expect(items.first { $0.kind == .goal }?.date == day(2026, 6, 5))
    }

    @Test("Rows with no date at all sort last")
    func undatedRowsSortLast() {
        let items = build(
            notes: [note(students: [alice])],
            goals: [goal(student: alice, createdAt: day(2026, 6, 5))]
        )
        #expect(items.map(\.kind) == [.goal, .flaggedNote])
        #expect(items.last?.date == .distantPast)
    }

    // MARK: - 7. The week

    @Test("The week holding Wednesday 10 June spans Monday 8 to Friday 12 and no further")
    func weekBounds() {
        let week = WatchListBuilder.week(containing: today)
        #expect(week.contains(day(2026, 6, 8)))
        #expect(week.contains(day(2026, 6, 12)))
        #expect(!week.contains(day(2026, 6, 5)))
        #expect(week.start > day(2026, 6, 5))
        #expect(week.end <= day(2026, 6, 15))
    }

    @Test("Touched this week means raised this week, never merely due this week")
    func touchedThisWeek() {
        let raisedTuesday = note(students: [alice], createdAt: day(2026, 6, 9, hour: 14))
        let raisedLastWeek = note(students: [alice], createdAt: day(2026, 6, 1))
        let oldTodoDueThursday = todo(
            "Watch Alice", students: [alice], createdAt: day(2026, 5, 20), dueDate: day(2026, 6, 11)
        )
        let all = build(notes: [raisedTuesday, raisedLastWeek], todos: [oldTodoDueThursday])
        let week = WatchListBuilder.touched(in: WatchListBuilder.week(containing: today), all)
        #expect(week.count == 1)
        #expect(week.first?.sourceID == raisedTuesday.id)
    }

    // MARK: - 8. Roster

    @Test("Restricting to the roster drops a withdrawn child's rows and keeps whole-class rows")
    func rosterRestriction() {
        let all = build(notes: [
            note(students: nil),
            note(students: [alice]),
            note(students: [ben])
        ])
        let kept = WatchListBuilder.restricted(toRoster: [alice], all)
        #expect(kept.count == 2)
        #expect(kept.contains { $0.studentID == nil })
        #expect(kept.contains { $0.studentID == alice })
        #expect(!kept.contains { $0.studentID == ben })
    }

    // MARK: - 9. Grouping

    @Test("Groups run by name with the whole class last, rows newest first inside each")
    func grouping() {
        let all = build(
            notes: [
                note("class", students: nil, createdAt: day(2026, 6, 9)),
                note("ben old", students: [ben], createdAt: day(2026, 6, 2)),
                note("ben new", students: [ben], createdAt: day(2026, 6, 8))
            ],
            goals: [goal("alice", student: alice, createdAt: day(2026, 6, 3))]
        )
        let names: [UUID: String] = [alice: "Alice L", ben: "Ben K"]
        let groups: [WatchGroup] = WatchListBuilder.grouped(all) { names[$0] ?? "?" }
        let expectedNames: [String] = ["Alice L", "Ben K", WatchGroup.wholeClassName]
        let expectedTexts: [String] = ["ben new", "ben old"]
        #expect(groups.map(\.name) == expectedNames)
        #expect(groups[1].items.map(\.text) == expectedTexts)
        #expect(groups.last?.studentID == nil)
    }
}
