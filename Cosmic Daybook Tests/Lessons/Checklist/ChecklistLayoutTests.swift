import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The checklist's Mac and iPad layout (plan, Phase 3): lesson names without their
/// section's prefix, sequence bands folded per area, student columns in level blocks,
/// and the Class column's tallies.
@Suite("Checklist layout")
@MainActor
struct ChecklistLayoutTests {

    // MARK: - Section prefix

    @Test("A section's name is dropped from the front of its lessons' names")
    func dropsSectionPrefix() {
        let name = ChecklistLessonDisplayName.displayName
        #expect(name("Stamp Game: Static Addition", "Stamp Game") == "Static Addition")
        #expect(name("Stamp Game Addition: Dynamic", "Stamp Game") == "Addition: Dynamic")
        #expect(name("stamp game – Division", "Stamp Game") == "Division")
        #expect(name("Étude: Rivers", "Etude") == "Rivers")
    }

    @Test("The full name stays when the section isn't a whole-word prefix, or nothing would be left")
    func keepsFullName() {
        let name = ChecklistLessonDisplayName.displayName
        #expect(name("Stamp Games Review", "Stamp Game") == "Stamp Games Review")
        #expect(name("Static Addition", "Stamp Game") == "Static Addition")
        #expect(name("Stamp Game", "Stamp Game") == "Stamp Game")
        #expect(name("Stamp Game:", "Stamp Game") == "Stamp Game:")
        #expect(name("Stamp Game: Static Addition", "") == "Stamp Game: Static Addition")
    }

    // MARK: - Collapsed sequences

    private func scratchDefaults() throws -> UserDefaults {
        let suite = "ChecklistLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Collapsed bands are remembered per area, under one key")
    func collapsedPersistsPerArea() throws {
        let defaults = try scratchDefaults()
        ChecklistCollapsedSequences.save(["preliminary", ""], area: "Math", defaults: defaults)
        ChecklistCollapsedSequences.save(["grammar"], area: "Language", defaults: defaults)

        #expect(ChecklistCollapsedSequences.load(area: "Math", defaults: defaults) == ["preliminary", ""])
        #expect(ChecklistCollapsedSequences.load(area: " math ", defaults: defaults) == ["preliminary", ""])
        #expect(ChecklistCollapsedSequences.load(area: "Language", defaults: defaults) == ["grammar"])
        #expect(ChecklistCollapsedSequences.load(area: "Geometry", defaults: defaults).isEmpty)

        let stored = try #require(defaults.dictionary(forKey: UserDefaultsKeys.checklistCollapsedSequences))
        #expect(Set(stored.keys) == ["math", "language"])

        ChecklistCollapsedSequences.save([], area: "Math", defaults: defaults)
        ChecklistCollapsedSequences.save([], area: "Language", defaults: defaults)
        #expect(defaults.object(forKey: UserDefaultsKeys.checklistCollapsedSequences) == nil)
    }

    @Test("The collapsed-sequences key is backed up with the other checklist settings")
    func collapsedKeyIsBackedUp() {
        #expect(BackupPreferencesService.preferenceKeys.contains(UserDefaultsKeys.checklistCollapsedSequences))
    }

    /// Math › Preliminary (Stamp Game section) and Decimal System; one student.
    private func makeViewModel(defaults: UserDefaults) throws -> (ClassAreaChecklistViewModel, [CDLesson]) {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let stamp = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game: Static Addition", area: "Math", sequence: "Preliminary"
        )
        stamp.section = "Stamp Game"
        let beads = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal System"
        )
        CoreDataTestHelpers.save(context)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return (viewModel, [stamp, beads])
    }

    @Test("Folding a band hides it, survives a reload, and a deep link opens it again")
    func foldAndReveal() throws {
        let defaults = try scratchDefaults()
        let (viewModel, _) = try makeViewModel(defaults: defaults)
        #expect(!viewModel.isCollapsed("Preliminary"))

        viewModel.toggleCollapsed("Preliminary")
        #expect(viewModel.isCollapsed("Preliminary"))
        #expect(!viewModel.isCollapsed("Decimal System"))
        #expect(ChecklistCollapsedSequences.load(area: "Math", defaults: defaults) == ["preliminary"])

        let (reloaded, lessons) = try makeViewModel(defaults: defaults)
        #expect(reloaded.isCollapsed("Preliminary"))

        let stampID = try #require(lessons[0].id)
        #expect(reloaded.sequence(containing: stampID) == "Preliminary")
        #expect(reloaded.expandSequence(containing: stampID))
        #expect(!reloaded.isCollapsed("Preliminary"))
        #expect(!reloaded.expandSequence(containing: stampID))
        #expect(ChecklistCollapsedSequences.load(area: "Math", defaults: defaults).isEmpty)
    }

    @Test("Collapse all folds every band; a search shows them open and still matches the full name")
    func collapseAllAndSearch() throws {
        let defaults = try scratchDefaults()
        let (viewModel, _) = try makeViewModel(defaults: defaults)
        let context = try #require(viewModel.lessons.first?.managedObjectContext)

        viewModel.setAllSequencesCollapsed(true)
        #expect(viewModel.areAllSequencesCollapsed)

        // "Stamp Game" is only in the hidden part of the shown name.
        viewModel.applyLessonQuery("stamp static", context: context)
        #expect(viewModel.visibleLessons.map(\.name) == ["Stamp Game: Static Addition"])
        #expect(!viewModel.isCollapsed("Preliminary"))
        #expect(!viewModel.areAllSequencesCollapsed)

        viewModel.clearFilters(context: context)
        #expect(viewModel.isCollapsed("Preliminary"))

        viewModel.setAllSequencesCollapsed(false)
        #expect(!viewModel.isCollapsed("Preliminary"))
        #expect(defaults.object(forKey: UserDefaultsKeys.checklistCollapsedSequences) == nil)
    }

    // MARK: - Level columns

    @Test("Columns run Upper, Adolescent, Lower, each block in roster order")
    func levelBlocks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeds: [(String, CDStudent.Level)] = [
            ("Lia", .lower), ("Uma", .upper), ("Ari", .adolescent),
            ("Lev", .lower), ("Una", .upper), ("Ula", .upper)
        ]
        let roster = seeds.map { name, level in
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test", level: level)
        }

        let columns = ChecklistStudentColumns(students: roster)

        #expect(columns.students.map(\.firstName) == ["Uma", "Una", "Ula", "Ari", "Lia", "Lev"])
        #expect(columns.blocks.map(\.level) == [.upper, .adolescent, .lower])
        #expect(columns.blocks.map(\.count) == [3, 1, 2])
        let ari = try #require(roster[2].id)
        let lia = try #require(roster[0].id)
        #expect(columns.blockStartIDs == [ari, lia])
    }

    @Test("One level is one block with no rule")
    func singleLevel() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let roster = ["A", "B"].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Test", level: .upper)
        }
        let columns = ChecklistStudentColumns(students: roster)
        #expect(columns.blocks.map(\.count) == [2])
        #expect(columns.blockStartIDs.isEmpty)
    }

    // MARK: - Class column

    @Test("The Class column counts mastered, in progress and planned; given is the first two")
    func rowSummary() {
        let summary = ChecklistRowSummary(statuses: [
            .mastered, .mastered, .presented, .practicing, .reviewing, .planned, .ready, .notReady
        ])
        #expect(summary.mastered == 2)
        #expect(summary.inProgress == 3)
        #expect(summary.planned == 1)
        #expect(summary.total == 8)
        #expect(summary.given == 5)
        #expect(summary.helpText == "5 of 8 have had it · 2 mastered · 1 planned")
    }

    @Test("Summaries cover the visible students, a missing state counting as Ready")
    func rowSummariesFromMatrix() throws {
        let lessonID = UUID()
        let ada = UUID()
        let bruno = UUID()
        let hidden = UUID()
        let mastered = StudentChecklistRowState(
            lessonID: lessonID, plannedItemID: nil, presentationLogID: nil, contractID: nil,
            isScheduled: false, isPresented: true, isActive: false, isComplete: false,
            isWorkActive: false, isWorkReview: false, lastActivityDate: nil, isStale: false,
            blockingReason: .none, isMastered: true
        )
        let matrix: ChecklistMatrixBuilder.Matrix = [ada: [lessonID: mastered], hidden: [lessonID: mastered]]

        let summaries = ChecklistRowSummary.summaries(matrix: matrix, studentIDs: [ada, bruno], lessonIDs: [lessonID])
        let summary = try #require(summaries[lessonID])
        #expect(summary.mastered == 1)
        #expect(summary.total == 2)
        #expect(summary.given == 1)
    }
}
