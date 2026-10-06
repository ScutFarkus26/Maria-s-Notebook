import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-05 fixes: when two copies of a parent were folded, a
// child whose id the kept copy already had stayed on the dropped copy and was
// deleted with it by the cascade, taking whatever only that child carried (a
// subtask ticked on that copy). Every child now moves; the child's own id pass
// folds the pair.

@Suite("Dedup moves same-id children too")
@MainActor
struct DedupSameIDChildTests {

    private let early = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private let late = Date(timeIntervalSinceReferenceDate: 780_000_600)

    @Test("A subtask ticked only on the dropped copy reaches the kept copy")
    func sameIDSubtaskMoves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let todoID = UUID()
        let subtaskID = UUID()
        let kept = CDTodoItem(context: context)
        kept.id = todoID
        kept.createdAt = early
        let dropped = CDTodoItem(context: context)
        dropped.id = todoID
        dropped.createdAt = late
        let open = CDTodoSubtask(context: context)
        open.id = subtaskID
        open.title = "Order paper"
        open.todo = kept
        let ticked = CDTodoSubtask(context: context)
        ticked.id = subtaskID
        ticked.title = "Order paper"
        ticked.isCompleted = true
        ticked.todo = dropped
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["TodoItem"])
        )

        #expect(results["TodoItem"] == 1)
        #expect(!ticked.isDeleted && ticked.managedObjectContext != nil)
        #expect(ticked.todo === kept)
        let subtasks = (kept.subtasks as? Set<CDTodoSubtask>) ?? []
        #expect(subtasks.count == 2)
        #expect(subtasks.contains { $0.isCompleted })
    }
}
