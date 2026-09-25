import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// See `RosterStoreTests` for why these poll instead of sleeping.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(10),
    _ condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// The lesson relationships section and the two parsha suggestion rows used to
/// fetch each lesson by id on every body pass. `lesson(id:in:)` answers from the
/// live catalog instead; it must hand back exactly what that fetch returned.
@Suite("LessonCatalog: per-context lesson lookup")
@MainActor
struct LessonCatalogContextLookupTests {

    @Test("A lesson the catalog holds is the object the fetch returned")
    func catalogHitIsTheFetchedObject() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        let lessons = ["Checkerboard", "Racks and Tubes", "Golden Beads"].map {
            CoreDataTestHelpers.seedLesson(in: context, name: $0, area: "Math", sequence: "Operations")
        }
        try context.save()
        let ids = try lessons.map { try #require($0.id) }
        try await waitUntil { ids.allSatisfy { catalog.lesson(id: $0) != nil } }

        for id in ids {
            let fetched = try #require(context.object(CDLesson.self, id: id))
            #expect(catalog.lesson(id: id, in: context) === fetched)
        }
        #expect(catalog.lesson(id: UUID(), in: context) == nil)
    }

    @Test("A lesson inserted this turn, before the catalog hears of it, is still found")
    func pendingInsertFallsBackToTheFetch() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let id = try #require(lesson.id)

        // Before anything fetches (a fetch can let the controller catch up).
        #expect(catalog.lesson(id: id) == nil)
        #expect(catalog.lesson(id: id, in: context) === lesson)
        #expect(context.object(CDLesson.self, id: id) === lesson)
    }

    @Test("A lesson deleted but not yet dropped from the catalog reads as gone, as the fetch did")
    func pendingDeleteReadsAsGone() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        try context.save()
        let id = try #require(lesson.id)
        try await waitUntil { catalog.lesson(id: id) != nil }

        context.delete(lesson)
        // Before anything fetches (a fetch can let the controller catch up).
        #expect(catalog.lesson(id: id) === lesson)
        #expect(catalog.lesson(id: id, in: context) == nil)
        #expect(context.object(CDLesson.self, id: id) == nil)
    }

    @Test("Another context gets its own object, exactly as its fetch would")
    func otherContextGetsItsOwnObject() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard")
        try context.save()
        let id = try #require(lesson.id)
        try await waitUntil { catalog.lesson(id: id) != nil }

        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = context.persistentStoreCoordinator
        let theirs = try #require(other.object(CDLesson.self, id: id))
        let found = try #require(catalog.lesson(id: id, in: other))
        #expect(found === theirs)
        #expect(found !== lesson)
    }
}
