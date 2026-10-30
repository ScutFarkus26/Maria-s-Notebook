import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// For Me to Do (2026-10-30): what the guide owes the child. Ticks on her open
// to-dos and new lines live in the meeting draft and are written only on
// Complete, in the same save as the rest of the meeting.
extension MeetingDraftStoreTests {

    /// An open to-do naming `child`, saved.
    @MainActor
    private func seedTodo(
        _ title: String, for child: UUID, recurrence: RecurrencePattern = .none, in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.studentIDsArray = [child.uuidString]
        todo.recurrence = recurrence
        if recurrence != .none { todo.dueDate = AppCalendar.startOfDay(Date()) }
        return todo
    }

    @Test("New lines are filed on Complete as to-dos naming her, with her tag, the due day and a note")
    @MainActor
    func newLinesFiledOnComplete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let child = try #require(student.id)
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        #expect(CoreDataTestHelpers.save(context))
        let due = AppCalendar.startOfDay(AppCalendar.addingDays(3, to: Date()))

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.newTodos = [
            MeetingNewTodo(text: "Find her a book on volcanoes", dueDate: due),
            MeetingNewTodo(text: "  Email her parents  ")
        ]
        #expect(draft.complete(context: context, saveCoordinator: .preview) { _ in nil })

        let filed = context.safeFetch(CDFetchRequest(CDTodoItem.self)).sorted { $0.title < $1.title }
        #expect(filed.map(\.title) == ["Email her parents", "Find her a book on volcanoes"])
        let note = "From the meeting on \(DateFormatters.shortMonthDay.string(from: Date()))"
        let tags = TodoTagHelper.syncStudentTags(existingTags: [], studentNames: ["Ora Levi"])
        #expect(!tags.isEmpty)
        for todo in filed {
            #expect(todo.studentIDsArray == [child.uuidString])
            #expect(todo.tagsArray == tags)
            #expect(todo.notes == note)
            #expect(!todo.isCompleted)
        }
        #expect(filed[0].dueDate == nil)
        #expect(filed[1].dueDate == due)
        #expect(draft.newTodos.isEmpty)
        #expect(MeetingPersistenceService.loadCurrent(studentID: child).isEmpty)
    }

    @Test("Ticked to-dos are completed on Complete, a repeating one rolls forward, and one gone meanwhile is skipped")
    @MainActor
    func tickedTodosCompletedOnComplete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let once = seedTodo("Order the map pins", for: child, in: context)
        let weekly = seedTodo("Check her journal", for: child, recurrence: .weekly, in: context)
        let deleted = seedTodo("Gone by Complete", for: child, in: context)
        let doneElsewhere = seedTodo("Done in Tide", for: child, in: context)
        let untouched = seedTodo("Not ticked", for: child, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.doneTodoIDs = Set([once, weekly, deleted, doneElsewhere].compactMap(\.id))

        // Meanwhile one is deleted and another completed somewhere else.
        context.delete(deleted)
        let stamp = Date(timeIntervalSince1970: 1_000)
        doneElsewhere.isCompleted = true
        doneElsewhere.completedAt = stamp
        #expect(CoreDataTestHelpers.save(context))

        #expect(draft.complete(context: context, saveCoordinator: .preview) { _ in nil })

        #expect(once.isCompleted && once.completedAt != nil)
        #expect(weekly.isCompleted)
        #expect(doneElsewhere.completedAt == stamp)
        #expect(!untouched.isCompleted)
        let open = context.safeFetch(CDFetchRequest(CDTodoItem.self)).filter { !$0.isCompleted }
        #expect(Set(open.map(\.title)) == ["Check her journal", "Not ticked"])
        let next = try #require(open.first { $0.title == "Check her journal" })
        #expect(next.studentIDsArray == [child.uuidString])
        #expect(next.dueDate != nil)
        #expect(draft.doneTodoIDs.isEmpty)
    }

    @Test("Nothing is written before Complete: ticks and new lines live only in the draft")
    @MainActor
    func nothingWrittenBeforeComplete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let todo = seedTodo("Order the map pins", for: child, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let todoID = try #require(todo.id)

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.doneTodoIDs = [todoID]
        draft.newTodos = [MeetingNewTodo(text: "Find her a book on volcanoes")]
        draft.flush()

        #expect(!context.hasChanges)
        #expect(!todo.isCompleted)
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 1)
        let stored = MeetingPersistenceService.loadCurrent(studentID: child)
        #expect(stored.doneTodoIDs == [todoID.uuidString])
        #expect(stored.newTodos?.map(\.text) == ["Find her a book on volcanoes"])
    }

    @Test("Clear Meeting drops the new lines and the ticks, and writes nothing")
    @MainActor
    func clearDropsTodoLinesAndTicks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let todo = seedTodo("Order the map pins", for: child, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.doneTodoIDs = [try #require(todo.id)]
        draft.newTodos = [MeetingNewTodo(text: "Find her a book on volcanoes")]
        draft.flush()
        #expect(draft.discard(context: context))

        #expect(draft.newTodos.isEmpty)
        #expect(draft.doneTodoIDs.isEmpty)
        #expect(!MeetingPersistenceService.hasDraft(studentID: child))
        #expect(!todo.isCompleted)
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 1)
    }

    @Test("A Complete whose save fails files no to-do and completes none; trying again files them once")
    @MainActor
    func failedCompleteFilesNoTodos() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let weekly = seedTodo("Check her journal", for: child, recurrence: .weekly, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.doneTodoIDs = [try #require(weekly.id)]
        draft.newTodos = [MeetingNewTodo(text: "Find her a book on volcanoes")]

        // A row missing a mandatory value, so the next save fails.
        let broken = CDAttendanceRecord(context: context)
        broken.date = Date()
        broken.setValue(nil, forKey: "studentID")
        #expect(!draft.complete(context: context, saveCoordinator: .preview) { _ in nil })
        context.processPendingChanges()
        #expect(context.insertedObjects == [broken])
        #expect(!weekly.isCompleted && weekly.completedAt == nil)
        #expect(draft.newTodos.count == 1 && draft.doneTodoIDs.count == 1)

        context.delete(broken)
        #expect(draft.complete(context: context, saveCoordinator: .preview) { _ in nil })
        let all = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        #expect(all.count == 3)
        #expect(all.filter { $0.title == "Find her a book on volcanoes" }.count == 1)
        #expect(all.filter { $0.title == "Check her journal" && !$0.isCompleted }.count == 1)
        #expect(weekly.isCompleted)
    }

    @Test("New lines and ticks survive storing and reloading the draft")
    @MainActor
    func todoFieldsSurviveReload() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let due = AppCalendar.startOfDay(AppCalendar.addingDays(7, to: Date()))
        let lines = [
            MeetingNewTodo(text: "Find her a book on volcanoes", dueDate: due),
            MeetingNewTodo(text: "Email her parents")
        ]
        let ticked: Set<UUID> = [UUID(), UUID()]

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.newTodos = lines
        draft.doneTodoIDs = ticked
        draft.flush()

        let reopened = MeetingDraftModel(studentID: child)
        reopened.load(context: context)
        #expect(reopened.newTodos == lines)
        #expect(reopened.doneTodoIDs == ticked)
    }

    @Test("A draft stored before For Me to Do, without its keys, still loads")
    func oldDraftWithoutTodoKeysLoads() throws {
        let name = "MeetingDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let child = UUID()
        let workID = UUID().uuidString
        let json = """
        {"isCompleted":false,"reflectionText":"Proud of the map","focusText":"","requestsText":"",\
        "guideNotesText":"","reviewedWorkIDs":["\(workID)"],"requestLessonIDs":[]}
        """
        defaults.set(Data(json.utf8), forKey: MeetingPersistenceService.draftKey(child))

        let draft = MeetingPersistenceService.loadCurrent(studentID: child, defaults: defaults)
        #expect(draft.reflectionText == "Proud of the map")
        #expect(draft.reviewedWorkIDs == [workID])
        #expect(draft.newTodos == nil)
        #expect(draft.doneTodoIDs == nil)
    }

    @Test("A draft holding only a new to-do or a tick isn't empty, and a meeting of only that is filed")
    @MainActor
    func todoOnlyDraftIsNotEmpty() throws {
        var line = MeetingPersistenceService.CurrentMeetingData()
        line.newTodos = [MeetingNewTodo(text: "Find her a book on volcanoes")]
        #expect(!line.isEmpty)
        var tick = MeetingPersistenceService.CurrentMeetingData()
        tick.doneTodoIDs = [UUID().uuidString]
        #expect(!tick.isEmpty)
        var blank = MeetingPersistenceService.CurrentMeetingData()
        blank.newTodos = [MeetingNewTodo(text: "  ")]
        #expect(blank.isEmpty)

        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        draft.newTodos = line.newTodos ?? []
        draft.flush()
        #expect(MeetingPersistenceService.hasDraft(studentID: child))
        #expect(draft.complete(context: context, saveCoordinator: .preview) { _ in nil })
        #expect(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).count == 1)
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 1)
    }

    @Test("Two windows on her meeting keep each other's new lines and ticks")
    @MainActor
    func twoWindowsKeepEachOthersTodos() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let ticked = UUID()
        let first = MeetingDraftModel(studentID: child)
        first.load(context: context)
        let second = MeetingDraftModel(studentID: child)
        second.load(context: context)

        first.newTodos = [MeetingNewTodo(text: "Typed in the first window")]
        first.flush()
        second.newTodos = [MeetingNewTodo(text: "Typed in the second window")]
        second.doneTodoIDs = [ticked]
        second.flush()

        let stored = MeetingPersistenceService.loadCurrent(studentID: child)
        #expect(stored.newTodos?.map(\.text) == ["Typed in the first window", "Typed in the second window"])
        #expect(stored.doneTodoIDs == [ticked.uuidString])

        // Removing a line in one window leaves the other's.
        first.takeUpStored()
        first.newTodos.removeAll { $0.text == "Typed in the first window" }
        first.flush()
        let after = MeetingPersistenceService.loadCurrent(studentID: child)
        #expect(after.newTodos?.map(\.text) == ["Typed in the second window"])
        #expect(after.doneTodoIDs == [ticked.uuidString])
    }

    @Test("For Me to Do lists only her open to-dos, Someday ones too, due ones first")
    @MainActor
    func sectionListsHerOpenTodos() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let later = seedTodo("No due day", for: child, in: context)
        let someday = seedTodo("Someday", for: child, in: context)
        someday.isSomeday = true
        let soon = seedTodo("Due soon", for: child, in: context)
        soon.dueDate = AppCalendar.startOfDay(AppCalendar.addingDays(1, to: Date()))
        let done = seedTodo("Done", for: child, in: context)
        done.isCompleted = true
        _ = seedTodo("Someone else's", for: UUID(), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listed = ForMeToDoSection.openTodos(context.safeFetch(CDFetchRequest(CDTodoItem.self)), for: child)
        #expect(listed.first === soon)
        #expect(Set(listed.map(\.title)) == [soon.title, later.title, someday.title])
    }
}
