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

/// `LessonCatalog` replaces the whole-table `@FetchRequest` every lesson view
/// used to hold, most of them only to look a lesson up by ID. These pin what
/// a view relies on: a save shows up in `all`, `byID` and `lesson(id:)` with
/// no manual refresh, deletion drops it, `lessons(area:sequence:)` matches the
/// way the presentation views did, and the two orders views list the catalog in.
@Suite("LessonCatalog: one live catalog per workspace")
@MainActor
struct LessonCatalogTests {

    @Test("A saved lesson appears in all, byID and lesson(id:) without a manual refresh")
    func savedLessonAppearsEverywhere() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let catalog = dependencies.lessonCatalog
        #expect(catalog.all.isEmpty)

        let lesson = CoreDataTestHelpers.seedLesson(
            in: dependencies.viewContext, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        try dependencies.viewContext.save()
        let id = try #require(lesson.id)

        try await waitUntil { catalog.lesson(id: id) != nil }
        #expect(catalog.all.contains(lesson))
        #expect(catalog.byID[id] === lesson)
        #expect(catalog.lesson(id: id) === lesson)
    }

    @Test("A deleted lesson leaves the catalog")
    func deletedLessonLeaves() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let catalog = dependencies.lessonCatalog
        let lesson = CoreDataTestHelpers.seedLesson(in: dependencies.viewContext)
        try dependencies.viewContext.save()
        let id = try #require(lesson.id)
        try await waitUntil { catalog.lesson(id: id) != nil }

        dependencies.viewContext.delete(lesson)
        try dependencies.viewContext.save()

        try await waitUntil { catalog.lesson(id: id) == nil }
        #expect(catalog.all.isEmpty)
    }

    @Test("lessons(area:sequence:) matches trimmed and case-insensitively, in orderInSequence order")
    func sequenceLookupMatchesLikeTheViewsDid() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog

        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Multiplication"
        )
        second.orderInSequence = 2
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: " math", sequence: "MULTIPLICATION "
        )
        first.orderInSequence = 1
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Division")
        try context.save()

        try await waitUntil { catalog.all.count == 3 }
        #expect(catalog.lessons(area: "Math", sequence: "multiplication").map(\.name) == ["Checkerboard", "Bead Frame"])
        #expect(catalog.lessons(area: "Math", sequence: "Fractions").isEmpty)
    }

    @Test("all is in curriculum order and sortedByAreaAndSortIndex in area, sort-index order")
    func ordersMatchTheViewsThatListTheCatalog() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog

        let geometry = CoreDataTestHelpers.seedLesson(
            in: context, name: "Triangles", area: "Geometry", sequence: "Shapes"
        )
        geometry.orderInSequence = 1
        geometry.sortIndex = 5
        let later = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Multiplication"
        )
        later.orderInSequence = 2
        later.sortIndex = 1
        let earlier = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        earlier.orderInSequence = 1
        earlier.sortIndex = 2
        try context.save()

        try await waitUntil { catalog.all.count == 3 }
        #expect(catalog.all.map(\.name) == ["Triangles", "Checkerboard", "Bead Frame"])
        #expect(catalog.sortedByAreaAndSortIndex.map(\.name) == ["Triangles", "Bead Frame", "Checkerboard"])
    }
}
