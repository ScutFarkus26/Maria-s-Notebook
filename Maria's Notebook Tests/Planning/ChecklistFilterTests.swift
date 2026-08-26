import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Checklist Lesson Matching")
struct ChecklistLessonFilterTests {

    @Test("A blank query matches every lesson")
    func blankQueryMatchesEverything() {
        #expect(ChecklistLessonFilter.tokens(from: "").isEmpty)
        #expect(ChecklistLessonFilter.tokens(from: "   ").isEmpty)
        #expect(
            ChecklistLessonFilter.matches(
                tokens: [], name: "Golden Beads", sequence: "Decimal System", section: ""
            )
        )
    }

    @Test("Matching ignores case and reaches the sequence and section")
    func matchesAcrossDisplayedFields() {
        let tokens = ChecklistLessonFilter.tokens(from: "ALGEBRA")
        #expect(
            ChecklistLessonFilter.matches(
                tokens: tokens, name: "Binomial Cube", sequence: "Algebra", section: ""
            )
        )
        #expect(
            ChecklistLessonFilter.matches(
                tokens: tokens, name: "Algebraic Peg Board", sequence: "Squaring", section: ""
            )
        )
        #expect(
            ChecklistLessonFilter.matches(
                tokens: tokens, name: "Trinomial Cube", sequence: "Squaring", section: "Pre-Algebra"
            )
        )
        #expect(
            !ChecklistLessonFilter.matches(
                tokens: tokens, name: "Golden Beads", sequence: "Decimal System", section: ""
            )
        )
    }

    @Test("Every token has to land somewhere, in any order and any field")
    func allTokensMustMatch() {
        let tokens = ChecklistLessonFilter.tokens(from: "frac add")
        #expect(
            ChecklistLessonFilter.matches(
                tokens: tokens, name: "Addition of Fractions", sequence: "Fractions", section: ""
            )
        )
        // "add" lands, "frac" does not.
        #expect(
            !ChecklistLessonFilter.matches(
                tokens: tokens, name: "Addition Strip Board", sequence: "Addition", section: ""
            )
        )
    }

    @Test("Matching ignores diacritics")
    func ignoresDiacritics() {
        let tokens = ChecklistLessonFilter.tokens(from: "etude")
        #expect(
            ChecklistLessonFilter.matches(
                tokens: tokens, name: "Étude de la Terre", sequence: "Geography", section: ""
            )
        )
    }
}

@Suite("Checklist Filtering")
@MainActor
struct ChecklistViewModelFilteringTests {

    /// Three students and five Math lessons across two sequences, plus one Language
    /// lesson so cross-area behaviour is observable.
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
        CoreDataTestHelpers.seedLesson(
            in: context, name: "Algebraic Sentence Analysis", area: "Language", sequence: "Grammar"
        )
        CoreDataTestHelpers.save(context)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return (viewModel, context)
    }

    @Test("Everything is visible before a filter is applied")
    func unfilteredShowsEverything() throws {
        let (viewModel, _) = try makeLoadedViewModel()
        #expect(viewModel.students.count == 3)
        #expect(viewModel.rosterStudents.count == 3)
        #expect(viewModel.visibleLessons.count == 5)
        #expect(viewModel.visibleSequences.sorted() == ["Algebra", "Decimal System"])
        #expect(viewModel.filterSummary == nil)
    }

    @Test("Typing a query hides the lessons and sequences that don't match")
    func lessonQueryHidesNonMatchingRows() throws {
        let (viewModel, context) = try makeLoadedViewModel()

        viewModel.applyLessonQuery("algebra", context: context)

        #expect(viewModel.visibleLessons.map(\.name).sorted() == ["Binomial Cube", "Trinomial Cube"])
        #expect(viewModel.visibleSequences == ["Algebra"])
        // The columns are untouched by a lesson query.
        #expect(viewModel.students.count == 3)
        #expect(viewModel.filterSummary == "2 of 5 lessons")
    }

    @Test("A sequence with no matches drops out but its lessons stay loaded")
    func filteringLeavesTheUnderlyingDataAlone() throws {
        let (viewModel, context) = try makeLoadedViewModel()

        viewModel.applyLessonQuery("beads", context: context)

        #expect(viewModel.visibleLessons.map(\.name) == ["Golden Beads"])
        #expect(viewModel.lessons.count == 5)
        #expect(viewModel.orderedSequences.sorted() == ["Algebra", "Decimal System"])
        #expect(viewModel.lessonsSequenced(sequence: "Decimal System").bySection[""]?.count == 1)
    }

    @Test("Picking students hides the other columns and keeps the roster intact")
    func studentFilterHidesOtherColumns() throws {
        let (viewModel, _) = try makeLoadedViewModel()
        let ada = try #require(viewModel.rosterStudents.first { $0.firstName == "Ada" })
        let chava = try #require(viewModel.rosterStudents.first { $0.firstName == "Chava" })

        viewModel.studentFilterIDs = [try #require(ada.id), try #require(chava.id)]
        viewModel.applyFilters()

        #expect(viewModel.students.map(\.firstName).sorted() == ["Ada", "Chava"])
        #expect(viewModel.rosterStudents.count == 3)
        #expect(viewModel.selectedFilterStudents.count == 2)
        #expect(viewModel.filterSummary == "2 of 3 students")
    }

    @Test("Both filters compose")
    func filtersCompose() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        let ada = try #require(viewModel.rosterStudents.first { $0.firstName == "Ada" })

        viewModel.applyLessonQuery("cube", context: context)
        viewModel.studentFilterIDs = [try #require(ada.id)]
        viewModel.applyFilters()

        #expect(viewModel.visibleLessons.count == 2)
        #expect(viewModel.students.map(\.firstName) == ["Ada"])
        #expect(viewModel.filterSummary == "2 of 5 lessons · 1 of 3 students")
    }

    @Test("Cells that a filter hides drop out of the selection")
    func filteringPrunesTheSelection() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        let ada = try #require(viewModel.rosterStudents.first { $0.firstName == "Ada" })
        let goldenBeads = try #require(viewModel.lessons.first { $0.name == "Golden Beads" })
        let binomial = try #require(viewModel.lessons.first { $0.name == "Binomial Cube" })

        viewModel.toggleSelection(student: ada, lesson: goldenBeads)
        viewModel.toggleSelection(student: ada, lesson: binomial)
        #expect(viewModel.selectedCells.count == 2)

        viewModel.applyLessonQuery("algebra", context: context)

        #expect(viewModel.selectedCells.count == 1)
        #expect(viewModel.selectedCells.first?.lessonID == binomial.id)
    }

    @Test("Clearing restores the whole area")
    func clearingRestoresEverything() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        let ada = try #require(viewModel.rosterStudents.first { $0.firstName == "Ada" })

        viewModel.applyLessonQuery("algebra", context: context)
        viewModel.studentFilterIDs = [try #require(ada.id)]
        viewModel.applyFilters()

        viewModel.clearFilters(context: context)

        #expect(viewModel.students.count == 3)
        #expect(viewModel.visibleLessons.count == 5)
        #expect(viewModel.visibleSequences.sorted() == ["Algebra", "Decimal System"])
        #expect(viewModel.lessonQuery.isEmpty)
        #expect(viewModel.filterSummary == nil)
        #expect(viewModel.otherAreaMatches.isEmpty)
    }

    @Test("An empty result points at the areas that do match")
    func emptyResultSuggestsOtherAreas() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        viewModel.selectedArea = "Language"
        viewModel.refreshMatrix(context: context)

        viewModel.applyLessonQuery("cube", context: context)

        #expect(viewModel.visibleLessons.isEmpty)
        #expect(viewModel.otherAreaMatches.map(\.area) == ["Math"])
        #expect(viewModel.otherAreaMatches.first?.count == 2)
    }

    @Test("Suggestions stay empty while the selected area has matches of its own")
    func noSuggestionsWhenTheAreaMatches() throws {
        let (viewModel, context) = try makeLoadedViewModel()

        viewModel.applyLessonQuery("algebra", context: context)

        #expect(!viewModel.visibleLessons.isEmpty)
        #expect(viewModel.otherAreaMatches.isEmpty)
    }

    @Test("A student who leaves the roster stops filtering the grid to nothing")
    func staleStudentFilterIsPruned() throws {
        let (viewModel, context) = try makeLoadedViewModel()
        viewModel.studentFilterIDs = [UUID()]

        viewModel.applyFilters()

        #expect(viewModel.studentFilterIDs.isEmpty)
        #expect(viewModel.students.count == 3)
        _ = context
    }
}
