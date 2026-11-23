import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// Set from an observation callback, which may run on any thread.
nonisolated private final class Fired: Sendable {
    private let flag = Mutex(false)
    var value: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

/// The state layer review's B5 (2026-11-22). The grid calls
/// `lessonsSequenced(sequence:)` for every band while it draws, and the first
/// call for a sequence fills a cache. The cache was tracked, so each fill
/// invalidated the bands already drawn. It is now kept out of tracking beside
/// a counter every lookup reads and every reset bumps: filling it tells no
/// one, and a filter or a refresh still redraws a band that only ever read
/// the cache.
@Suite("Checklist: the lessons-per-sequence cache and what it tells views")
@MainActor
struct ChecklistLessonsCacheObservationTests {

    /// Three students and five Math lessons across two sequences.
    private func makeLoadedViewModel() throws -> (ClassAreaChecklistViewModel, NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        for name in ["Ada", "Bruno", "Chava"] {
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test")
        }
        for (name, sequence) in [
            ("Binomial Cube", "Algebra"),
            ("Trinomial Cube", "Algebra"),
            ("Golden Beads", "Decimal System"),
            ("Stamp Game", "Decimal System"),
            ("Bead Frame", "Decimal System")
        ] {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: sequence)
        }
        CoreDataTestHelpers.save(context)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return (viewModel, context)
    }

    /// A band that found its lessons in the cache, tracked the way a view
    /// tracks what it read while drawing.
    private func trackCachedLookup(_ viewModel: ClassAreaChecklistViewModel, sequence: String) -> Fired {
        // Filled first, outside tracking, so the tracked call is a cache hit.
        _ = viewModel.lessonsSequenced(sequence: sequence)
        let fired = Fired()
        _ = withObservationTracking { viewModel.lessonsSequenced(sequence: sequence) } onChange: { fired.set() }
        return fired
    }

    @Test("Filling the cache for another sequence fires nothing")
    func cacheMissFiresNothing() throws {
        let (viewModel, _) = try makeLoadedViewModel()
        let fired = trackCachedLookup(viewModel, sequence: "Algebra")

        #expect(viewModel.lessonsSequenced(sequence: "Decimal System").lessonCount == 3)
        #expect(!fired.value, "filling the cache while drawing invalidated a band already drawn")
    }

    @Test("A filter change tells a band that only read the cache")
    func filterChangeFires() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        let fired = trackCachedLookup(viewModel, sequence: "Algebra")

        viewModel.applyLessonQuery("trinomial", context: context)
        #expect(fired.value, "a filter change didn't reach a band reading the cache")
        #expect(viewModel.lessonsSequenced(sequence: "Algebra").lessons.map(\.name) == ["Trinomial Cube"])
    }

    @Test("A refresh after a remote change tells a band that only read the cache")
    func refreshFires() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        let fired = trackCachedLookup(viewModel, sequence: "Algebra")

        CoreDataTestHelpers.seedLesson(in: context, name: "Cubing", area: "Math", sequence: "Algebra")
        CoreDataTestHelpers.save(context)
        viewModel.refreshMatrix(context: context)
        #expect(fired.value, "a refresh didn't reach a band reading the cache")
        #expect(viewModel.lessonsSequenced(sequence: "Algebra").lessonCount == 3)
    }
}
