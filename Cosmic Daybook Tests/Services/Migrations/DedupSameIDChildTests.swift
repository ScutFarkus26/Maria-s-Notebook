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
        // Subtasks are retired (no class since 2026-11), but their rows stay
        // and still move with their to-do.
        let open = NSEntityDescription.insertNewObject(forEntityName: "TodoSubtask", into: context)
        open.setValue(subtaskID, forKey: "id")
        open.setValue("Order paper", forKey: "title")
        open.setValue(kept, forKey: "todo")
        let ticked = NSEntityDescription.insertNewObject(forEntityName: "TodoSubtask", into: context)
        ticked.setValue(subtaskID, forKey: "id")
        ticked.setValue("Order paper", forKey: "title")
        ticked.setValue(true, forKey: "isCompleted")
        ticked.setValue(dropped, forKey: "todo")
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["TodoItem"])
        )

        #expect(results["TodoItem"] == 1)
        #expect(!ticked.isDeleted && ticked.managedObjectContext != nil)
        #expect(ticked.value(forKey: "todo") as? CDTodoItem === kept)
        let subtasks = (kept.value(forKey: "subtasks") as? Set<NSManagedObject>) ?? []
        #expect(subtasks.count == 2)
        #expect(subtasks.contains { $0.value(forKey: "isCompleted") as? Bool == true })
    }
}
