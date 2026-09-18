import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The post-import dedup pass runs on a fresh background context 5 s after
// every CloudKit import, all school day. A clean store (no duplicates) must
// not leave live objects behind in that context: every row the pass
// materialises is a fault fired, a row decoded, and memory held until the
// context goes away. Efficiency pass 2026-09-17.

@Suite("Deduplication Footprint")
@MainActor
struct DeduplicationFootprintTests {

    private func seedCleanStore(lessons: Int, tracks: Int) throws -> CoreDataStack {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        for index in 0..<lessons {
            CoreDataTestHelpers.seedLesson(
                in: context, name: "Lesson \(index)", area: "Area \(index % 7)", sequence: "Seq \(index % 3)"
            )
        }
        for index in 0..<tracks {
            let track = CDTrackEntity(context: context)
            track.title = "Track \(index)"
        }
        CoreDataTestHelpers.save(context)
        return stack
    }

    @Test("A full pass over a clean store registers no objects in the working context")
    func cleanPassLeavesNoRegisteredObjects() async throws {
        let stack = try seedCleanStore(lessons: 300, tracks: 30)
        let bgContext = stack.newBackgroundContext()

        let (results, registered) = await bgContext.perform {
            let results = DataCleanupService.deduplicateAllModels(using: bgContext)
            return (results, bgContext.registeredObjects.count)
        }

        #expect(results.isEmpty)
        #expect(registered == 0, "the pass left \(registered) objects registered")
    }
}
