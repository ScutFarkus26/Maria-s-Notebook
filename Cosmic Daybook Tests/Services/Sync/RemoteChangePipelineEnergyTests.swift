import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the sync-pipeline energy changes: remote-change notifications are
/// folded into one history pass per window, and the dedup pass's own save
/// names the entities the history processor used to report for it.
@Suite("Remote-change pipeline: coalescing and dedup authorship")
@MainActor
struct RemoteChangePipelineEnergyTests {

    private func waitUntil(timeout: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("A burst of remote-change notifications runs one history pass")
    func burstRunsOnePass() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        var passes = 0
        for _ in 0..<8 {
            stack.scheduleCoalescedRemoteChangePass { passes += 1 }
        }
        #expect(await waitUntil { passes == 1 && stack.pendingRemoteChangePass == nil })
        #expect(passes == 1)

        // A notification after the window closes gets its own pass.
        stack.scheduleCoalescedRemoteChangePass { passes += 1 }
        #expect(await waitUntil { passes == 2 })
    }

    @Test("The dedup pass reports every entity its saves wrote, across part-way saves")
    func savedEntityNamesCoverEverySave() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let kept = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "T")
        let doomed = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "T")
        #expect(CoreDataTestHelpers.save(context))

        let saved = SavedEntityNames(observing: context)
        context.delete(doomed)
        #expect(CoreDataTestHelpers.save(context))
        kept.firstName = "Ada Mae"
        CoreDataTestHelpers.seedNote(in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(saved.finish() == ["Student", "Note"])

        // Nothing after finish() is collected.
        CoreDataTestHelpers.seedNote(in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(saved.finish() == ["Student", "Note"])
    }

    @Test("History written by the app's own author is invisible to the remote filter")
    func ownAuthorIsFiltered() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("author-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: directory.appendingPathComponent("a.sqlite"))
        let store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        let start = try #require(stack.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: [store]))

        // The dedup context is now tagged like this.
        let tagged = stack.container.newBackgroundContext()
        tagged.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        let author = PersistentHistoryProcessor.transactionAuthor
        let remoteLooking: Int = try await tagged.perform {
            let student = CDStudent(context: tagged)
            student.firstName = "Tagged"
            student.lastName = "Write"
            try tagged.save()
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: start)
            let filter = try #require(NSPersistentHistoryTransaction.fetchRequest)
            filter.predicate = NSPredicate(format: "author != %@", author)
            request.fetchRequest = filter
            let result = try tagged.execute(request) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.count ?? -1
        }
        #expect(remoteLooking == 0)
    }
}
