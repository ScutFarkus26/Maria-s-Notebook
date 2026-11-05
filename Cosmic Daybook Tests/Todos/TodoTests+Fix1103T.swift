import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Todos screen (bug hunt 2026-11-03, #50, #51, #58), on the lists
/// round-two Simplify left it: Check-ins, Not yet in Tide, Done and the Tide
/// lists. #49 (checklists) and #57 (Someday) fixed parts of the screen that
/// round retired, so their tests went with them.
@Suite("Todos: Clear Completed, the selection and the headings (2026-11-03)")
@MainActor
struct TodoFix1103Tests {

    private static var today: Date { AppCalendar.startOfDay(Date()) }

    private static func todo(
        _ title: String, due: Int? = nil, scheduled: Int? = nil, done: Bool = false,
        tideList: String? = nil, in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.dueDate = due.map { AppCalendar.addingDays($0, to: today) }
        todo.scheduledDate = scheduled.map { AppCalendar.addingDays($0, to: today) }
        todo.isCompleted = done
        todo.tideLink = tideList.map { TideActionLink(file: $0, text: title).string }
        return todo
    }

    // MARK: - #50 Clear Completed

    @Test("Clear Completed takes only the completed to-dos of the list on screen")
    func clearCompletedIsScopedToTheList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let school = "Areas/School/To do.md"
        let doneSchool = Self.todo("Order paint", done: true, tideList: school, in: context)
        let doneHome = Self.todo("Print number cards", done: true, tideList: "Areas/Home/To do.md", in: context)
        let openSchool = Self.todo("Hang paintings", tideList: school, in: context)
        let all = [doneSchool, doneHome, openSchool]

        let list = TodoListScope(tideList: school)
        #expect(list.completedToClear(from: all).map(\.objectID) == [doneSchool.objectID])

        let checkIns = TodoListScope(filter: .checkIns)
        #expect(checkIns.completedToClear(from: all).isEmpty)

        let done = TodoListScope(filter: .done)
        #expect(Set(done.completedToClear(from: all).map(\.objectID)) == [doneSchool.objectID, doneHome.objectID])

        let searched = TodoListScope(filter: .done, searchText: "paint")
        #expect(searched.completedToClear(from: all).map(\.objectID) == [doneSchool.objectID])
    }

    // MARK: - #51 The selection follows the list

    @Test("Picking another list or filter clears the selection")
    func selectionClearsOnListChange() {
        var selection = TodoBatchSelection()
        selection.show(TodoListScope(filter: .checkIns))
        selection.ids = [UUID(), UUID()]

        selection.show(TodoListScope(filter: .done))
        #expect(selection.ids.isEmpty)

        selection.ids = [UUID()]
        selection.show(TodoListScope(tideList: "Areas/School/To do.md"))
        #expect(selection.ids.isEmpty)
    }

    @Test("Typing in the search clears the selection; showing the same list again keeps it")
    func selectionClearsOnSearchButNotOnSameList() {
        var selection = TodoBatchSelection()
        let checkIns = TodoListScope(filter: .checkIns)
        selection.show(checkIns)
        let picked: Set<UUID> = [UUID(), UUID()]
        selection.ids = picked

        selection.show(checkIns)
        #expect(selection.ids == picked)

        selection.show(TodoListScope(filter: .checkIns, searchText: "paint"))
        #expect(selection.ids.isEmpty)
    }

    // MARK: - #58 The headings

    @Test("A to-do due today but planned for tomorrow is listed under Today")
    func dueTodayPlannedTomorrowIsUnderToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let dueToday = Self.todo("Hand in the report", due: 0, scheduled: 1, in: context)
        let overdue = Self.todo("Call the plumber", due: -2, scheduled: 1, in: context)
        let plannedTomorrow = Self.todo("Set up the easel", scheduled: 1, in: context)
        let plannedTodayDueLater = Self.todo("Read the new album", due: 4, scheduled: 0, in: context)
        let now = Date()

        // A Tide list (no notebook filter) groups by date.
        #expect(TodoMainView.sectionTitle(for: dueToday, filter: nil, today: now) == "Today")
        #expect(TodoMainView.sectionTitle(for: overdue, filter: nil, today: now) == "Overdue")
        #expect(TodoMainView.sectionTitle(for: plannedTomorrow, filter: nil, today: now) == "Tomorrow")
        #expect(TodoMainView.sectionTitle(for: plannedTodayDueLater, filter: nil, today: now) == "Today")
        // Check-ins read day by day after today; Done is one heading.
        #expect(TodoMainView.sectionTitle(for: dueToday, filter: .checkIns, today: now) == "Today")
        #expect(TodoMainView.sectionTitle(for: plannedTomorrow, filter: .done, today: now) == "Completed")
    }
}
