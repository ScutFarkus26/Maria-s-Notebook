import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Todo Linked-Work Completion")
@MainActor
struct TodoLinkedWorkCompletionTests {

    @Test("Completing a work's todos completes only its open linked todos")
    func completesOnlyLinkedOpenTodos() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let workID = UUID()
        let linked = CDTodoItem(context: context)
        linked.title = "Check the map"
        linked.linkedWorkItemID = workID.uuidString
        let lowercased = CDTodoItem(context: context)
        lowercased.title = "Check the map labels"
        lowercased.linkedWorkItemID = workID.uuidString.lowercased()
        let other = CDTodoItem(context: context)
        other.title = "Check the chain"
        other.linkedWorkItemID = UUID().uuidString
        let unlinked = CDTodoItem(context: context)
        unlinked.title = "Order paint"
        CoreDataTestHelpers.save(context)

        let completed = TodoCompletionService.completeTodosLinked(toWork: workID, in: context)

        #expect(Set(completed.map(\.objectID)) == [linked.objectID, lowercased.objectID])
        #expect(linked.isCompleted && linked.completedAt != nil)
        #expect(lowercased.isCompleted)
        #expect(!other.isCompleted)
        #expect(!unlinked.isCompleted)
    }

    @Test("A repeating linked todo's next occurrence keeps the link")
    func nextOccurrenceKeepsLink() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let workID = UUID()
        let weekly = CDTodoItem(context: context)
        weekly.title = "Check the map"
        weekly.recurrence = .weekly
        weekly.dueDate = Date()
        weekly.linkedWorkItemID = workID.uuidString
        CoreDataTestHelpers.save(context)

        TodoCompletionService.completeTodosLinked(toWork: workID, in: context)

        let all = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        let next = try #require(all.first { !$0.isCompleted })
        #expect(all.count == 2)
        #expect(weekly.isCompleted)
        #expect(next.linkedWorkItemID == workID.uuidString)
    }

    @Test("Already completed linked todos are left alone")
    func skipsCompleted() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let workID = UUID()
        let done = CDTodoItem(context: context)
        done.title = "Checked"
        done.linkedWorkItemID = workID.uuidString
        done.isCompleted = true
        let stamp = Date(timeIntervalSince1970: 1_000)
        done.completedAt = stamp
        CoreDataTestHelpers.save(context)

        let completed = TodoCompletionService.completeTodosLinked(toWork: workID, in: context)

        #expect(completed.isEmpty)
        #expect(done.completedAt == stamp)
    }

    // MARK: - Wired completion

    /// Open work with one open linked todo, saved.
    private func seedLinkedWork(
        in context: NSManagedObjectContext, recurrence: RecurrencePattern = .none
    ) -> (CDWorkModel, CDTodoItem) {
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game")
        work.id = UUID()
        work.status = .active
        let todo = CDTodoItem(context: context)
        todo.title = "Check the stamp game"
        todo.dueDate = Date()
        todo.recurrence = recurrence
        todo.linkedWorkItemID = work.id?.uuidString
        CoreDataTestHelpers.save(context)
        return (work, todo)
    }

    @Test("Recording a check-in completes the work's linked todos")
    func checkInCompletesLinkedTodos() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let (work, todo) = seedLinkedWork(in: context)
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), purpose: "progressCheck", in: context)

        try WorkCheckInService(context: context).markCompleted(checkIn)

        #expect(checkIn.status == .completed)
        #expect(todo.isCompleted)
    }

    @Test("Logging the work completes its linked todos, and Undo reopens them and removes the next occurrence")
    func workLogCompletesAndUndoRestores() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let (work, todo) = seedLinkedWork(in: context, recurrence: .weekly)

        let receipt = try WorkLogService.log([.init(work: work)], context: context)

        #expect(todo.isCompleted)
        #expect(receipt.token.completedTodos == [todo.objectID])
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 2)

        try WorkLogService.undo(receipt.token, context: context)

        let all = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        #expect(all.map(\.objectID) == [todo.objectID])
        #expect(!todo.isCompleted)
        #expect(todo.completedAt == nil)
    }
}
