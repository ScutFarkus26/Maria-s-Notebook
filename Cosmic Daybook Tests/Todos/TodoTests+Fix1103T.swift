import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Todos screen and repeating to-dos (bug hunt 2026-11-03, #49, #50,
/// #51, #57, #58).
@Suite("Todos: checklists, Clear Completed, the selection and Today (2026-11-03)")
@MainActor
struct TodoFix1103Tests {

    private static var today: Date { AppCalendar.startOfDay(Date()) }

    private static func todo(
        _ title: String, due: Int? = nil, scheduled: Int? = nil, someday: Bool = false, done: Bool = false,
        tags: [String] = [], recurrence: RecurrencePattern = .none, in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.dueDate = due.map { AppCalendar.addingDays($0, to: today) }
        todo.scheduledDate = scheduled.map { AppCalendar.addingDays($0, to: today) }
        todo.isSomeday = someday
        todo.isCompleted = done
        todo.tagsArray = tags
        todo.recurrence = recurrence
        return todo
    }

    @discardableResult
    private static func addSubtask(
        _ title: String, ticked: Bool = false, to todo: CDTodoItem, in context: NSManagedObjectContext
    ) -> CDTodoSubtask {
        let subtask = CDTodoSubtask(context: context)
        subtask.title = title
        subtask.orderIndex = Int64((todo.subtasks?.count ?? 0))
        subtask.isCompleted = ticked
        subtask.completedAt = ticked ? Date() : nil
        todo.addToSubtasks(subtask)
        return subtask
    }

    private static func checklist(of todo: CDTodoItem) -> [CDTodoSubtask] {
        ((todo.subtasks as? Set<CDTodoSubtask>) ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private static func openTodos(in context: NSManagedObjectContext) -> [CDTodoItem] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(format: "isCompleted == NO")
        return context.safeFetch(request)
    }

    // MARK: - #49 A repeat keeps its checklist

    @Test("A repeating to-do's next occurrence gets its checklist, every item unticked")
    func nextOccurrenceCopiesChecklistUnticked() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weekly = Self.todo("Tidy the art shelf", due: 0, recurrence: .weekly, in: context)
        Self.addSubtask("Wash brushes", ticked: true, to: weekly, in: context)
        Self.addSubtask("Refill paper", to: weekly, in: context)
        #expect(context.safeSave())

        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())

        let copy = try #require(Self.openTodos(in: context).first)
        let items = Self.checklist(of: copy)
        #expect(items.map(\.title) == ["Wash brushes", "Refill paper"])
        #expect(items.allSatisfy { !$0.isCompleted && $0.completedAt == nil })
        // The done one keeps its own ticks.
        #expect(Self.checklist(of: weekly).map(\.isCompleted) == [true, false])
    }

    @Test("Tick, untick, tick on a to-do with a checklist still leaves one next occurrence")
    func tickUntickTickWithChecklist() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weekly = Self.todo("Tidy the art shelf", due: 0, recurrence: .weekly, in: context)
        Self.addSubtask("Wash brushes", to: weekly, in: context)
        #expect(context.safeSave())

        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        TodoCompletionService.reopen(weekly)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).map(\.objectID) == [weekly.objectID])

        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).count == 1)
    }

    @Test("Unticking keeps a next occurrence whose checklist was ticked since")
    func untickKeepsCopyWithTickedChecklist() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weekly = Self.todo("Tidy the art shelf", due: 0, recurrence: .weekly, in: context)
        Self.addSubtask("Wash brushes", to: weekly, in: context)
        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        let copy = try #require(Self.openTodos(in: context).first)
        let item = try #require(Self.checklist(of: copy).first)
        item.isCompleted = true
        #expect(context.safeSave())

        TodoCompletionService.reopen(weekly)
        #expect(context.safeSave())
        #expect(Set(Self.openTodos(in: context).map(\.objectID)) == [weekly.objectID, copy.objectID])
    }

    // MARK: - #50 Clear Completed

    @Test("Clear Completed takes only the completed to-dos of the list on screen")
    func clearCompletedIsScopedToTheList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let doneArt = Self.todo("Order paint", done: true, tags: ["Art"], in: context)
        let doneMath = Self.todo("Print number cards", done: true, tags: ["Math"], in: context)
        let openArt = Self.todo("Hang paintings", tags: ["Art"], in: context)
        let all = [doneArt, doneMath, openArt]

        let art = TodoListScope(tag: "Art")
        #expect(art.completedToClear(from: all).map(\.objectID) == [doneArt.objectID])

        let inbox = TodoListScope(filter: .inbox)
        #expect(inbox.completedToClear(from: all).isEmpty)

        let completed = TodoListScope(filter: .completed)
        #expect(Set(completed.completedToClear(from: all).map(\.objectID)) == [doneArt.objectID, doneMath.objectID])

        let searched = TodoListScope(filter: .completed, searchText: "paint")
        #expect(searched.completedToClear(from: all).map(\.objectID) == [doneArt.objectID])
    }

    // MARK: - #51 The selection follows the list

    @Test("Picking another list or filter clears the selection")
    func selectionClearsOnListChange() {
        var selection = TodoBatchSelection()
        selection.show(TodoListScope(filter: .today))
        selection.ids = [UUID(), UUID()]

        selection.show(TodoListScope(tag: "Art"))
        #expect(selection.ids.isEmpty)

        selection.ids = [UUID()]
        selection.show(TodoListScope(filter: .upcoming))
        #expect(selection.ids.isEmpty)

        selection.ids = [UUID()]
        selection.show(TodoListScope(tideList: "Areas/School/To do.md"))
        #expect(selection.ids.isEmpty)
    }

    @Test("Typing in the search clears the selection; showing the same list again keeps it")
    func selectionClearsOnSearchButNotOnSameList() {
        var selection = TodoBatchSelection()
        let today = TodoListScope(filter: .today)
        selection.show(today)
        let picked: Set<UUID> = [UUID(), UUID()]
        selection.ids = picked

        selection.show(today)
        #expect(selection.ids == picked)

        selection.show(TodoListScope(filter: .today, searchText: "paint"))
        #expect(selection.ids.isEmpty)
    }

    // MARK: - #57 Someday and a passed deadline

    @Test("A Someday to-do whose deadline has come shows in Today as overdue")
    func somedayWithPassedDeadlineIsInToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let overdue = Self.todo("Return library books", due: -3, someday: true, in: context)
        let dueToday = Self.todo("Send the field-trip form", due: 0, someday: true, in: context)
        let dueLater = Self.todo("Plan the spring play", due: 5, someday: true, in: context)
        let noDeadline = Self.todo("Repaint the bench", someday: true, in: context)

        #expect(TodoListFilter.today.matches(overdue))
        #expect(TodoListFilter.today.matches(dueToday))
        #expect(!TodoListFilter.today.matches(dueLater))
        #expect(!TodoListFilter.today.matches(noDeadline))
        // Still in Someday, and never in Upcoming.
        for todo in [overdue, dueToday, dueLater, noDeadline] {
            #expect(TodoListFilter.someday.matches(todo), "\(todo.title)")
            #expect(!TodoListFilter.upcoming.matches(todo), "\(todo.title)")
        }
        #expect(TodoMainView.sectionTitle(for: overdue, filter: .today, today: Date()) == "Overdue")
    }

    // MARK: - #58 Today's headings

    @Test("Under Today, a to-do due today but planned for tomorrow is listed under Today")
    func dueTodayPlannedTomorrowIsUnderToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let dueToday = Self.todo("Hand in the report", due: 0, scheduled: 1, in: context)
        let overdue = Self.todo("Call the plumber", due: -2, scheduled: 1, in: context)
        let plannedTomorrow = Self.todo("Set up the easel", scheduled: 1, in: context)
        let plannedTodayDueLater = Self.todo("Read the new album", due: 4, scheduled: 0, in: context)
        let now = Date()

        #expect(TodoMainView.sectionTitle(for: dueToday, filter: .today, today: now) == "Today")
        #expect(TodoMainView.sectionTitle(for: overdue, filter: .today, today: now) == "Overdue")
        #expect(TodoMainView.sectionTitle(for: plannedTomorrow, filter: .all, today: now) == "Tomorrow")
        #expect(TodoMainView.sectionTitle(for: plannedTodayDueLater, filter: .today, today: now) == "Today")
    }
}
