import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 6 Post-Tests: Conflict Resolution & Offline")
@MainActor
final class Phase6PostTests {

    // MARK: - Token Tracking

    @Test("PersistentHistoryProcessor init loads without crash")
    func processorInit() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let processor = PersistentHistoryProcessor(container: stack.container)
        // Construction and an empty-history pass must both complete safely.
        await processor.processRemoteChanges()
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

    @Test("purgeOldHistory is a no-op until CloudKit has successfully exported")
    func purgeSkipsWithoutExportDate() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let processor = PersistentHistoryProcessor(container: stack.container)

        let exportKey = UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate
        let purgeKey = UserDefaultsKeys.persistentHistoryLastPurgeDate
        let savedExport = UserDefaults.standard.object(forKey: exportKey)
        let savedPurge = UserDefaults.standard.object(forKey: purgeKey)
        defer {
            UserDefaults.standard.set(savedExport, forKey: exportKey)
            UserDefaults.standard.set(savedPurge, forKey: purgeKey)
        }
        UserDefaults.standard.removeObject(forKey: exportKey)
        UserDefaults.standard.removeObject(forKey: purgeKey)

        await processor.purgeOldHistory()

        // Without a recorded export the purge must not run, and must not
        // record a purge date — the mirroring delegate's history cursor
        // could still point anywhere in the un-exported history.
        #expect(UserDefaults.standard.object(forKey: purgeKey) == nil)
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

    @Test("Secondary stacks (in-memory, Sample Class) do not create a history processor")
    func secondaryStackHasNoProcessor() throws {
        // History tokens are per-store and every processor persists its token
        // under the same UserDefaults key, so only the primary on-disk stack
        // may own a processor — a secondary stack's saves would clobber the
        // primary cursor with one referencing a different store file.
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(stack.historyProcessor == nil)
    }
}
