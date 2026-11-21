import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A repeating to-do's next occurrence takes an id worked out from the one
/// completed (plan "Domain logic fixes", R25): two devices completing the same
/// to-do before they sync make the same next occurrence, which the same-id
/// cleanup folds into one, and ticking again after an untick makes no
/// second copy.
@Suite("Todos: a repeat's series")
@MainActor
struct TodoSeriesIDTests {

    private static var today: Date { AppCalendar.startOfDay(Date()) }

    private static func weekly(_ title: String, id: UUID, in context: NSManagedObjectContext) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.id = id
        todo.title = title
        todo.recurrence = .weekly
        todo.dueDate = today
        return todo
    }

    private static func openTodos(in context: NSManagedObjectContext) -> [CDTodoItem] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(format: "isCompleted == NO")
        return context.safeFetch(request)
    }

    @Test("Two devices' next occurrences of one to-do fold into one, with the Tide link kept")
    func twoDevicesNextOccurrencesFold() throws {
        let id = UUID()
        // The same to-do on two devices, each completing it before they sync.
        let phone = try CoreDataTestHelpers.makeContext()
        let mac = try CoreDataTestHelpers.makeContext()
        TodoCompletionService.complete(Self.weekly("Water the plants", id: id, in: phone))
        TodoCompletionService.complete(Self.weekly("Water the plants", id: id, in: mac))
        let onPhone = try #require(Self.openTodos(in: phone).first)
        let onMac = try #require(Self.openTodos(in: mac).first)
        #expect(onPhone.id != nil && onPhone.id == onMac.id, "both next occurrences have the same id")
        #expect(onPhone.id != id)

        // iCloud brings the Mac's copy, sent to Tide there, to the phone.
        let arrived = Self.weekly(onMac.title, id: try #require(onMac.id), in: phone)
        arrived.dueDate = onMac.dueDate
        arrived.tideLink = "tide://action/water"
        #expect(phone.safeSave())
        #expect(Self.openTodos(in: phone).count == 2)

        DataCleanupService.deduplicate(CDTodoItem.self, using: phone, merge: DataCleanupService.mergeTodoItem)
        #expect(phone.safeSave())
        let left = Self.openTodos(in: phone)
        #expect(left.count == 1)
        #expect(left.first?.tideLink == "tide://action/water")
    }

    @Test("Unticking a renamed to-do keeps its copy, and ticking it again makes no second one")
    func retickFindsTheCopyByID() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let todo = Self.weekly("Water the plants", id: UUID(), in: context)
        TodoCompletionService.complete(todo)
        #expect(context.safeSave())
        let copy = try #require(Self.openTodos(in: context).first)
        #expect(copy.id == todo.id.map { TodoCompletionService.nextOccurrenceID(of: $0) })

        // Renamed: nobody can tell which of the two was, so the copy stays.
        todo.title = "Water the classroom plants"
        TodoCompletionService.reopen(todo)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).count == 2)

        // Tick again: the copy it made is still here, so there's no second one.
        TodoCompletionService.complete(todo)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).map(\.objectID) == [copy.objectID])
    }

    @Test("Unticking straight after a tick takes back the copy, found by its id")
    func reopenTakesBackTheCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let todo = Self.weekly("Water the plants", id: UUID(), in: context)
        TodoCompletionService.complete(todo)
        #expect(context.safeSave())
        TodoCompletionService.reopen(todo)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).map(\.objectID) == [todo.objectID])

        TodoCompletionService.complete(todo)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).first?.id == todo.id.map { TodoCompletionService.nextOccurrenceID(of: $0) })
    }
}
