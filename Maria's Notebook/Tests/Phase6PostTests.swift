import Foundation
import CoreData
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Phase 6 Post-Tests: Conflict Resolution & Offline")
@MainActor
final class Phase6PostTests {

    // MARK: - Token Tracking

    @Test("PersistentHistoryProcessor init loads without crash")
    func processorInit() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let processor = PersistentHistoryProcessor(container: stack.container)
        #expect(processor != nil)
    }

    @Test("processRemoteChanges completes without crash on empty history")
    func processRemoteChangesEmpty() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let processor = PersistentHistoryProcessor(container: stack.container)
        // Should complete gracefully with no transactions to process
        await processor.processRemoteChanges()
    }

    // MARK: - Author Filtering

    @Test("Transaction author constant is set correctly")
    func transactionAuthorConstant() {
        #expect(PersistentHistoryProcessor.transactionAuthor == "MariasNotebook")
    }

    @Test("View context has transactionAuthor set")
    func viewContextAuthor() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(stack.viewContext.transactionAuthor == PersistentHistoryProcessor.transactionAuthor)
    }

    @Test("Background context has transactionAuthor set")
    func backgroundContextAuthor() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let bgCtx = stack.newBackgroundContext()
        #expect(bgCtx.transactionAuthor == PersistentHistoryProcessor.transactionAuthor)
    }

    // MARK: - History Cleanup

    @Test("purgeOldHistory completes without crash on empty history")
    func purgeOldHistory() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let processor = PersistentHistoryProcessor(container: stack.container)
        await processor.purgeOldHistory()
    }

    // MARK: - End-to-End Merge

    @Test("Insert on background context merges to viewContext")
    func endToEndMerge() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let bgCtx = stack.newBackgroundContext()

        await bgCtx.perform {
            let student = CDStudent(context: bgCtx)
            student.firstName = "Phase6"
            student.lastName = "MergeTest"
            try? bgCtx.save()
        }

        // Allow merge to propagate (automaticallyMergesChangesFromParent)
        try await Task.sleep(for: .milliseconds(200))

        let request: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
        request.predicate = NSPredicate(format: "firstName == %@", "Phase6")
        let results = stack.viewContext.safeFetch(request)
        #expect(results.count == 1)
        #expect(results.first?.lastName == "MergeTest")
    }

    // MARK: - CoreDataStack Integration

    @Test("CoreDataStack has historyProcessor after init")
    func stackHasProcessor() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(stack.historyProcessor != nil)
    }
}
#endif
