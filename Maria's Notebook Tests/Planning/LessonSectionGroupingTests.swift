import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Pins the bucketing the Checklist grid and the scope-and-sequence map share.
///
/// The two screens used to spell this out separately, and a guide reading one
/// against the other found lessons in different places. These tests hold the
/// three promises that made them disagree: sections fold case-insensitively,
/// unsectioned lessons trail the named bands, and each band runs in curriculum
/// order rather than the order the lessons happened to be fetched in.
///
/// Every case here uses an area and sequence no stored order exists for, so the
/// bands fall back to alphabetical and nothing depends on the guide's own
/// arrangement.
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
        LessonSectionGrouping.bands(for: lessons, area: Self.area, sequence: Self.sequence)
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

    @Test("Unsectioned lessons trail the named bands")
    func unsectionedComesLast() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Unfiled", section: "", order: 0),
            lesson(context, "Bead Bars", section: "Beads", order: 1),
            lesson(context, "Stamps", section: "Stamp Game", order: 2)
        ]

        #expect(bands(lessons).map(\.name) == ["Beads", "Stamp Game", ""])
    }

    @Test("With no stored order the named bands are alphabetical")
    func namedBandsAreAlphabeticalByDefault() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Stamps", section: "Stamp Game", order: 0),
            lesson(context, "Bead Bars", section: "Beads", order: 1)
        ]

        #expect(bands(lessons).map(\.name) == ["Beads", "Stamp Game"])
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

    // MARK: - Names offered to the reorder sheet

    @Test("The reorder sheet is offered one row per folded section")
    func sectionNamesMatchTheBands() throws {
        let context = try makeContext()
        let lessons = [
            lesson(context, "Short Chain", section: "Chains", order: 0),
            lesson(context, "Long Chain", section: "chains", order: 1),
            lesson(context, "Unfiled", section: "", order: 2),
            lesson(context, "Bead Bars", section: "Beads", order: 3)
        ]

        #expect(LessonSectionGrouping.sectionNames(in: lessons) == ["Beads", "Chains"])
    }
}

/// The order stores back both grids. It caches to keep UserDefaults off the
/// render path, and the cache used to hold the *merged* result — so one call
/// made while a filter was narrowing the lesson set threw away the saved
/// position of every section absent at that moment, for both screens, for the
/// rest of the launch.
@Suite("Filter Order Store Caching")
@MainActor
struct FilterOrderStoreCachingTests {

    private static let area = "TestArea-\(UUID().uuidString)"
    private static let sequence = "TestSequence"

    /// Removes what these tests wrote. The store lives in the real defaults, and
    /// the suite's area name is unique per run, so matching on it clears the
    /// entries without this test having to know the key format.
    private static func clearStoredOrders() {
        let needle = area.lowercased()
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(needle) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        FilterOrderStore.resetCache()
    }

    @Test("A narrowed read doesn't strip the saved order for the next reader")
    func narrowedReadLeavesTheSavedOrderIntact() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        let saved = ["Chains", "Beads", "Stamp Game"]
        FilterOrderStore.saveSectionOrder(saved, for: Self.area, sequence: Self.sequence)
        FilterOrderStore.resetCache()

        // The Checklist, mid-filter, asks about the one section still on screen.
        let narrowed = FilterOrderStore.loadSectionOrder(
            for: Self.area, sequence: Self.sequence, existing: ["Beads"]
        )
        #expect(narrowed == ["Beads"])

        // The map then asks about the whole sequence and must still get the saved order.
        let full = FilterOrderStore.loadSectionOrder(
            for: Self.area, sequence: Self.sequence, existing: ["Beads", "Chains", "Stamp Game"]
        )
        #expect(full == saved)
    }

    @Test("A section with no saved place is appended, not inserted")
    func unknownSectionsFollowTheSavedOnes() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSectionOrder(["Chains", "Beads"], for: Self.area, sequence: Self.sequence)
        FilterOrderStore.resetCache()

        let order = FilterOrderStore.loadSectionOrder(
            for: Self.area, sequence: Self.sequence, existing: ["Beads", "Chains", "Fractions"]
        )
        #expect(order == ["Chains", "Beads", "Fractions"])
    }

    @Test("A section keeps its saved place when the grid spells it differently")
    func savedPlaceSurvivesADifferentSpelling() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSectionOrder(
            ["Introduction", "Equivalence", "Addition"], for: Self.area, sequence: Self.sequence
        )
        FilterOrderStore.resetCache()

        // The grid folds its bands from the lessons themselves, so it can hand back a
        // spelling the saved order doesn't use. That must not read as a new section.
        let order = FilterOrderStore.loadSectionOrder(
            for: Self.area, sequence: Self.sequence, existing: ["Addition", "equivalence", "Introduction"]
        )
        #expect(order == ["Introduction", "equivalence", "Addition"])
    }

    @Test("Two spellings of one name yield one entry, not two")
    func spellingsCollapseToOneEntry() {
        defer { Self.clearStoredOrders() }
        FilterOrderStore.resetCache()
        FilterOrderStore.saveSectionOrder(["Equivalence"], for: Self.area, sequence: Self.sequence)
        FilterOrderStore.resetCache()

        let order = FilterOrderStore.loadSectionOrder(
            for: Self.area, sequence: Self.sequence, existing: ["Equivalence", "equivalence"]
        )
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
