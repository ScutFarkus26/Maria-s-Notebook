import Foundation
import CoreData
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Phase 4 Pre-Tests: Stability & Memory")
@MainActor
final class Phase4PreTests {

    // MARK: - Memory Leak Detection

    @Test("CoreDataStack creates and tears down without leaking")
    func coreDataStackNoLeak() throws {
        let checker: LeakChecker<CoreDataStack>
        try autoreleasepool {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            checker = LeakChecker(stack)
            // Use the stack briefly to ensure it's fully initialized
            _ = stack.viewContext
        }
        #expect(!checker.hasLeak, "CoreDataStack leaked after teardown")
    }

    @Test("AppDependencies creates and tears down without leaking")
    func appDependenciesNoLeak() throws {
        let checker: LeakChecker<AppDependencies>
        try autoreleasepool {
            let deps = try CoreDataTestHelpers.makeDependencies()
            checker = LeakChecker(deps)
            _ = deps.viewContext
        }
        #expect(!checker.hasLeak, "AppDependencies leaked after teardown")
    }

    // MARK: - Crash Resistance

    @Test("10 rapid CoreDataStack create/destroy cycles without crash")
    func rapidStackCycles() throws {
        for _ in 0..<10 {
            autoreleasepool {
                let stack = try? CoreDataTestHelpers.makeInMemoryStack()
                #expect(stack != nil, "CoreDataStack creation should not fail")
                _ = stack?.viewContext
            }
        }
    }

    @Test("Concurrent background context creation does not hang", .timeLimit(.seconds(5)))
    func concurrentBackgroundContexts() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    let ctx = stack.newBackgroundContext()
                    #expect(ctx.concurrencyType == .privateQueueConcurrencyType)
                }
            }
        }
    }

    // MARK: - CRUD Operations

    @Test("Insert, fetch, and delete CDStudent without crash")
    func studentCRUD() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        // Insert
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Alice", lastName: "Smith")
        #expect(CoreDataTestHelpers.save(context))

        // Fetch
        let request: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
        request.predicate = NSPredicate(format: "firstName == %@", "Alice")
        let results = context.safeFetch(request)
        #expect(results.count == 1)
        #expect(results.first?.lastName == "Smith")

        // Delete
        context.delete(student)
        #expect(CoreDataTestHelpers.save(context))

        let afterDelete = context.safeFetch(request)
        #expect(afterDelete.isEmpty)
    }

    @Test("Insert, fetch, and delete CDNote without crash")
    func noteCRUD() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let note = CoreDataTestHelpers.seedNote(in: context, body: "Hello world")
        #expect(CoreDataTestHelpers.save(context))

        let request: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        let results = context.safeFetch(request)
        #expect(results.count == 1)
        #expect(results.first?.body == "Hello world")

        context.delete(note)
        #expect(CoreDataTestHelpers.save(context))
    }

    @Test("RepositoryContainer creation from test stack does not crash")
    func repositoryContainerCreation() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let repos = RepositoryContainer(context: stack.viewContext, saveCoordinator: nil)
        // Access a repository to ensure lazy initialization works
        _ = repos.students
        _ = repos.notes
    }
}
#endif
