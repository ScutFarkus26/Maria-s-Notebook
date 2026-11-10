import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the bucketing the Checklist grid and the scope-and-sequence map share.
///
/// The two screens used to spell this out separately, and a guide reading one
/// against the other found lessons in different places. These tests hold the
/// promises that made them disagree: sections fold case-insensitively, each band
/// runs in curriculum order rather than the order the lessons happened to be
/// fetched in — and (2026-11-09) the bands themselves sit where their earliest
/// lesson falls, with lessons that have no section placed by their own order
/// rather than trailing the rest.
@Suite("Lesson Section Grouping")
@MainActor
struct LessonSectionGroupingTests {

    private static let area = "TestArea-\(UUID().uuidString)"
    private static let sequence = "TestSequence"

    private func makeContext() throws -> NSManagedObjectContext {
        FilterOrderStore.resetCache()
        return try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @discardableResult
    private func lesson(
        _ context: NSManagedObjectContext,
        _ name: String,
        section: String,
        order: Int64
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: name, area: Self.area, sequence: Self.sequence
        )
        lesson.id = UUID()
        lesson.section = section
        lesson.orderInSequence = order
        return lesson
    }

    private func bands(_ lessons: [CDLesson]) -> [LessonSectionGrouping.Band] {
        LessonSectionGrouping.bands(for: lessons)
    }

    // MARK: - Folding

    @Test("Two spellings of one section are one band")
    func sectionsFoldCaseInsensitively() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Short Chain", section: "Chains", order: 0),
            lesson(context, "Long Chain", section: "chains", order: 1)
        ]

        let result = bands(lessons)
        #expect(result.count == 1, "expected one band, got \(result.map(\.name))")
        #expect(result.first?.lessons.count == 2)
    }

    @Test("A folded band is labelled with the spelling that comes first in curriculum order")
    func foldedBandTakesTheEarliestSpelling() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Long Chain", section: "chains", order: 5),
            lesson(context, "Short Chain", section: "Chains", order: 1)
        ]

        #expect(bands(lessons).first?.name == "Chains")
    }

    // MARK: - Band order

    @Test("Sections run in the order of their earliest lesson, not alphabetically")
    func sectionsFollowTheirEarliestLesson() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Stamps", section: "Stamp Game", order: 0),
            lesson(context, "Bead Bars", section: "Beads", order: 1),
            lesson(context, "Abacus", section: "Abacus", order: 2)
        ]

        #expect(bands(lessons).map(\.name) == ["Stamp Game", "Beads", "Abacus"])
    }

    @Test("A section split by another is drawn whole where its first lesson falls")
    func splitSectionStaysWhole() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Bead Bars", section: "Beads", order: 0),
            lesson(context, "Stamps", section: "Stamp Game", order: 1),
            lesson(context, "Bead Squares", section: "Beads", order: 2)
        ]

        let result = bands(lessons)
        #expect(result.map(\.name) == ["Beads", "Stamp Game"])
        #expect(result.first?.lessons.map(\.name) == ["Bead Bars", "Bead Squares"])
    }

    @Test("Lessons with no section sit where their order puts them, not at the bottom")
    func unsectionedSitsInPlace() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Introduction", section: "", order: 0),
            lesson(context, "Bead Bars", section: "Beads", order: 1),
            lesson(context, "Story", section: "", order: 2),
            lesson(context, "Song", section: "", order: 3),
            lesson(context, "Stamps", section: "Stamp Game", order: 4),
            lesson(context, "Review", section: "", order: 5)
        ]

        let result = bands(lessons)
        #expect(result.map(\.name) == ["", "Beads", "", "Stamp Game", ""])
        #expect(result.map { $0.lessons.map(\.name) } == [
            ["Introduction"], ["Bead Bars"], ["Story", "Song"], ["Stamps"], ["Review"]
        ])
    }

    @Test("A sequence with no sections at all is one unnamed band")
    func noSectionsYieldsASingleBand() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Second", section: "", order: 1),
            lesson(context, "First", section: "", order: 0)
        ]

        let result = bands(lessons)
        #expect(result.map(\.name) == [""])
        #expect(result.first?.lessons.map(\.name) == ["First", "Second"])
    }

    // MARK: - Lesson order inside a band

    @Test("Lessons inside a band run in curriculum order, not fetch order")
    func lessonsRunInCurriculumOrder() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Third", section: "Beads", order: 2),
            lesson(context, "First", section: "Beads", order: 0),
            lesson(context, "Second", section: "Beads", order: 1)
        ]

        #expect(bands(lessons).first?.lessons.map(\.name) == ["First", "Second", "Third"])
    }

    @Test("Lessons sharing a position fall back to name")
    func tiesBreakOnName() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Beta", section: "Beads", order: 0),
            lesson(context, "Alpha", section: "Beads", order: 0)
        ]

        #expect(bands(lessons).first?.lessons.map(\.name) == ["Alpha", "Beta"])
    }

    // MARK: - Totality

    @Test("Every lesson lands in exactly one band")
    func everyLessonIsPlacedOnce() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Unfiled", section: "", order: 0),
            lesson(context, "Short Chain", section: "Chains", order: 1),
            lesson(context, "Long Chain", section: "chains", order: 2),
            lesson(context, "Bead Bars", section: "Beads", order: 3)
        ]

        let placed = bands(lessons).flatMap(\.lessons)
        #expect(placed.count == lessons.count, "a lesson was dropped or drawn twice")
        #expect(Set(placed.map(\.name)) == Set(lessons.map(\.name)))
    }
}

/// The order store backs both grids' sub-area order. It caches to keep
/// UserDefaults off the render path, and the cache used to hold the *merged*
/// result — so one call made while a filter was narrowing the lesson set threw
/// away the saved position of everything absent at that moment, for both
/// screens, for the rest of the launch.
@Suite("Filter Order Store Caching")
@MainActor
struct FilterOrderStoreCachingTests {

    private static let area = "TestArea-\(UUID().uuidString)"
    /// Removes what these tests wrote. The order lives in the real synced
    /// preferences, and the suite's area name is unique per run, so matching on
    /// it clears the entries.
    private static func clearStoredOrders() {
        let store = SyncedPreferencesStore.shared
        for key in store.storedKeys(withPrefix: FilterOrderStore.sequenceOrderKeyPrefix)
        where key.contains(area.lowercased()) {
            store.remove(key: key)
        }
        FilterOrderStore.resetCache()
    }

    @Test("A sub-area with no saved place is appended, not inserted")
    func unknownSequencesFollowTheSavedOnes() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSequenceOrder(["Chains", "Beads"], for: Self.area)
        FilterOrderStore.resetCache()

        let order = FilterOrderStore.loadSequenceOrder(for: Self.area, existing: ["Beads", "Chains", "Fractions"])
        #expect(order == ["Chains", "Beads", "Fractions"])
    }

    @Test("A sub-area keeps its saved place when the grid spells it differently")
    func savedPlaceSurvivesADifferentSpelling() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSequenceOrder(["Introduction", "Equivalence", "Addition"], for: Self.area)
        FilterOrderStore.resetCache()

        let order = FilterOrderStore.loadSequenceOrder(
            for: Self.area, existing: ["Addition", "equivalence", "Introduction"]
        )
        #expect(order == ["Introduction", "equivalence", "Addition"])
    }

    @Test("Two spellings of one name yield one entry, not two")
    func spellingsCollapseToOneEntry() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSequenceOrder(["Equivalence"], for: Self.area)
        FilterOrderStore.resetCache()

        let order = FilterOrderStore.loadSequenceOrder(for: Self.area, existing: ["Equivalence", "equivalence"])
        #expect(order == ["Equivalence"], "a band would have been drawn twice")
    }

    @Test("A narrowed sequence read doesn't strip the saved order either")
    func narrowedSequenceReadLeavesTheSavedOrderIntact() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        let saved = ["Early Work", "Preliminary", "Ungrouped"]
        FilterOrderStore.saveSequenceOrder(saved, for: Self.area)
        FilterOrderStore.resetCache()

        _ = FilterOrderStore.loadSequenceOrder(for: Self.area, existing: ["Preliminary"])
        let full = FilterOrderStore.loadSequenceOrder(
            for: Self.area, existing: ["Early Work", "Preliminary", "Ungrouped"]
        )
        #expect(full == saved)
    }
}
