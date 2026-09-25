import CoreData
import Foundation
import Synchronization
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

/// Set from an observation callback, which may run on any thread.
nonisolated private final class Fired: Sendable {
    private let flag = Mutex(false)
    var value: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

/// The Lessons screen used to hold its own live fetch of every lesson, sorted
/// area, sort index, order in sequence, beside the catalog's fetch of the same
/// table. It now reads `sortedByAreaSortIndexAndOrder`, and the catalog builds
/// its rarely read orders on first read after a change instead of on every
/// change. These pin that the screen's order is the old fetch's order on its
/// three keys (ties, which the store left unordered, now follow `all`), and
/// that a view reading only a derived order is still invalidated by every
/// change and reads a current value.
@Suite("LessonCatalog: the Lessons screen's order and the lazily built orders")
@MainActor
struct LessonCatalogScreenOrderTests {

    /// The three keys the Lessons screen's fetch sorted on.
    private struct ScreenKey: Equatable, CustomStringConvertible {
        let area: String
        let sortIndex: Int64
        let orderInSequence: Int64

        init(_ lesson: CDLesson) {
            area = lesson.area
            sortIndex = lesson.sortIndex
            orderInSequence = lesson.orderInSequence
        }

        var description: String { "(\(area)|\(sortIndex)|\(orderInSequence))" }
    }

    /// The fetch `LessonsRootView` held before it read the catalog.
    private func screenFetch(_ context: NSManagedObjectContext) throws -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
        return try context.fetch(request)
    }

    @discardableResult
    private func lesson(
        _ context: NSManagedObjectContext,
        _ name: String,
        area: String,
        sequence: String,
        sortIndex: Int64,
        order: Int64 = 0
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        lesson.sortIndex = sortIndex
        lesson.orderInSequence = order
        return lesson
    }

    /// Areas that differ only by case, padding or accent, sort indexes out of
    /// step with sequence order, and three lessons tied on all three keys.
    private func seed(_ context: NSManagedObjectContext) throws {
        lesson(context, "Tie Zeta", area: "Math", sequence: "Chains", sortIndex: 3, order: 1)
        lesson(context, "Tie Beta", area: "Math", sequence: "Beads", sortIndex: 3, order: 1)
        lesson(context, "Tie Alpha", area: "Math", sequence: "Beads", sortIndex: 3, order: 1)
        lesson(context, "Stamp Game", area: "Math", sequence: "Operations", sortIndex: 1, order: 4)
        lesson(context, "Bead Frame", area: "Math", sequence: "Beads", sortIndex: 1, order: 2)
        lesson(context, "Golden Beads", area: "Math", sequence: "Beads", sortIndex: 0, order: 9)
        lesson(context, "Padded", area: "Math ", sequence: "Beads", sortIndex: 0, order: 0)
        lesson(context, "Lower", area: "math", sequence: "Beads", sortIndex: 0, order: 0)
        lesson(context, "Triangles", area: "Geometry", sequence: "Shapes", sortIndex: 2, order: 0)
        lesson(context, "Solids", area: "Geometry", sequence: "Shapes", sortIndex: 2, order: 1)
        lesson(context, "Accented", area: "Géométrie", sequence: "Formes", sortIndex: 0, order: 0)
        lesson(context, "No Area", area: "", sequence: "", sortIndex: 5, order: 0)
        lesson(context, "No Area Either", area: "", sequence: "", sortIndex: 0, order: 3)
        try context.save()
    }

    @Test("The screen order is the screen's old fetch order on its three keys; ties follow sequence, then name")
    func screenOrderMatchesTheOldFetch() throws {
        // On SQLite, so the old order is the store's own ORDER BY.
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        try seed(context)
        let catalog = LessonCatalog(context: context)

        let expected = try screenFetch(context)
        let ordered = catalog.sortedByAreaSortIndexAndOrder
        #expect(ordered.count == expected.count)
        #expect(Set(ordered.map(\.objectID)) == Set(expected.map(\.objectID)))
        #expect(ordered.map(ScreenKey.init) == expected.map(ScreenKey.init))
        #expect(ordered.filter { $0.name.hasPrefix("Tie ") }.map(\.name) == ["Tie Alpha", "Tie Beta", "Tie Zeta"])
    }

    @Test("The screen order follows edits the way the old fetch did")
    func screenOrderFollowsEdits() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        try seed(context)
        try await waitUntil { catalog.all.count == 13 }
        let seeded = try screenFetch(context).map(ScreenKey.init)
        #expect(catalog.sortedByAreaSortIndexAndOrder.map(ScreenKey.init) == seeded)

        let moved = try #require(catalog.all.first { $0.name == "Golden Beads" })
        moved.sortIndex = 7
        let rehomed = try #require(catalog.all.first { $0.name == "Solids" })
        rehomed.area = "Math"
        rehomed.sortIndex = 3
        rehomed.orderInSequence = 0
        CoreDataTestHelpers.seedLesson(in: context, name: "New", area: "Geometry", sequence: "Shapes")
        let before = catalog.version
        try context.save()
        try await waitUntil { catalog.version > before }

        #expect(catalog.all.count == 14)
        let edited = try screenFetch(context).map(ScreenKey.init)
        #expect(catalog.sortedByAreaSortIndexAndOrder.map(ScreenKey.init) == edited)
    }

    @Test("A reader of only a derived order is invalidated by every change and then reads the current value")
    func derivedOrdersInvalidateAndRefresh() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let catalog = dependencies.lessonCatalog
        let first = lesson(context, "Checkerboard", area: "Math", sequence: "Multiplication", sortIndex: 2, order: 1)
        let second = lesson(context, "Bead Frame", area: "Math", sequence: "multiplication ", sortIndex: 1, order: 2)
        try context.save()
        try await waitUntil { catalog.all.count == 2 }

        let readers: [(name: String, read: @MainActor () -> [CDLesson])] = [
            ("sortedByAreaAndSortIndex", { catalog.sortedByAreaAndSortIndex }),
            ("sortedByAreaSortIndexAndOrder", { catalog.sortedByAreaSortIndexAndOrder }),
            ("lessons(area:sequence:)", { catalog.lessons(area: "math", sequence: "Multiplication") })
        ]
        for (step, reader) in readers.enumerated() {
            let fired = Fired()
            _ = withObservationTracking { reader.read() } onChange: { fired.set() }
            // Swap the two lessons' positions on every key a derived order reads.
            let lead = step.isMultiple(of: 2) ? first : second
            let trail = step.isMultiple(of: 2) ? second : first
            lead.sortIndex = 5
            lead.orderInSequence = 5
            trail.sortIndex = 0
            trail.orderInSequence = 0
            try context.save()
            try await waitUntil { fired.value }
            #expect(fired.value, "\(reader.name): no invalidation")
            #expect(reader.read().map(\.name) == [trail.name, lead.name], "\(reader.name): stale after the change")
        }
    }
}
