import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The cell menu's Presented toggles and Remove Plan take a child off a presentation
/// through `PresentationRecordCleanup` (`ChecklistRosterRemoval`): promoted year-plan
/// entries go back to planned, the presentation's rows for her go, and a mastery mark
/// is never deleted.
@Suite("Checklist unmark presented")
@MainActor
struct ChecklistUnmarkPresentedTests {

    /// Ada and Bruno; Math › Decimal 0 (first in its sequence, so nothing blocks it).
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let lesson: CDLesson

        var lessonID: String { lesson.id?.uuidString ?? "" }

        func status(_ student: CDStudent) -> ChecklistDisplayStatus? {
            viewModel.state(for: student, lesson: lesson)?.displayStatus
        }

        func assignments() -> [CDLessonAssignment] {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
            return context.safeFetch(request)
        }

        func rows(_ student: CDStudent) -> [CDLessonPresentation] {
            let request = CDFetchRequest(CDLessonPresentation.self)
            request.predicate = NSPredicate(
                format: "studentID == %@ AND lessonID == %@", student.cloudKitKey, lessonID
            )
            return context.safeFetch(request)
        }

        func promotedEntry(_ student: CDStudent, into plan: CDLessonAssignment) throws -> CDYearPlanEntry {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = student.cloudKitKey
            entry.lessonID = lessonID
            entry.status = .promoted
            entry.promotedAssignmentID = try #require(plan.id).uuidString
            try context.save()
            return entry
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal 0", area: "Math", sequence: "Decimal")
        try context.save()

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(viewModel: viewModel, context: context, ada: ada, bruno: bruno, lesson: lesson)
    }

    @Test("Mark Presented then Unmark Presented leaves nothing behind")
    func toggleRoundTrips() throws {
        let fixture = try makeFixture()
        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        #expect(fixture.status(fixture.ada) == .presented)
        #expect(fixture.assignments().count == 1)
        #expect(fixture.rows(fixture.ada).count == 1)

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        #expect(fixture.status(fixture.ada) == .ready)
        #expect(fixture.assignments().isEmpty)
        #expect(fixture.rows(fixture.ada).isEmpty)

        fixture.viewModel.togglePreviouslyPresented(
            student: fixture.ada, lesson: fixture.lesson, context: fixture.context
        )
        fixture.viewModel.togglePreviouslyPresented(
            student: fixture.ada, lesson: fixture.lesson, context: fixture.context
        )
        #expect(fixture.assignments().isEmpty)
        #expect(fixture.rows(fixture.ada).isEmpty)
    }

    @Test("Unmark Presented on a mastered cell keeps the mastery mark")
    func unmarkKeepsMastery() throws {
        let fixture = try makeFixture()
        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        #expect(fixture.status(fixture.ada) == .mastered)

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(fixture.status(fixture.ada) == .mastered)
        #expect(fixture.rows(fixture.ada).contains { $0.state == .proficient && $0.masteredAt != nil })
    }

    @Test("Unmark Presented on a recorded group keeps a mark filed on its row and the classmate's rows")
    func unmarkRecordedPresentation() throws {
        let fixture = try makeFixture()
        let given = CDLessonAssignment(context: fixture.context)
        given.lessonID = fixture.lessonID
        given.studentIDs = [fixture.ada.cloudKitKey, fixture.bruno.cloudKitKey]
        given.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
        let givenID = try #require(given.id).uuidString
        let adaMark = CDLessonPresentation(context: fixture.context)
        adaMark.studentID = fixture.ada.cloudKitKey
        adaMark.lessonID = fixture.lessonID
        adaMark.presentationID = givenID
        adaMark.state = .proficient
        adaMark.masteredAt = Date(timeIntervalSince1970: 1_781_000_000)
        let brunoRow = CDLessonPresentation(context: fixture.context)
        brunoRow.studentID = fixture.bruno.cloudKitKey
        brunoRow.lessonID = fixture.lessonID
        brunoRow.presentationID = givenID
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(given.studentIDs == [fixture.bruno.cloudKitKey])
        #expect(!adaMark.isDeleted)
        #expect(adaMark.state == .proficient)
        #expect(fixture.status(fixture.ada) == .mastered)
        #expect(fixture.rows(fixture.bruno).count == 1)
        #expect(fixture.status(fixture.bruno) == .presented)
    }

    @Test("Unmark Presented takes off the presentation's own row for her, not her others")
    func unmarkDeletesOnlyThatPresentationsRows() throws {
        let fixture = try makeFixture()
        let given = CDLessonAssignment(context: fixture.context)
        given.lessonID = fixture.lessonID
        given.studentIDs = [fixture.ada.cloudKitKey, fixture.bruno.cloudKitKey]
        given.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
        let ownRow = CDLessonPresentation(context: fixture.context)
        ownRow.studentID = fixture.ada.cloudKitKey
        ownRow.lessonID = fixture.lessonID
        ownRow.presentationID = try #require(given.id).uuidString
        // The guide set her to practicing in the sheet: not a row the toggle made.
        let practicing = CDLessonPresentation(context: fixture.context)
        practicing.studentID = fixture.ada.cloudKitKey
        practicing.lessonID = fixture.lessonID
        practicing.state = .practicing
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.togglePresented(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)

        #expect(ownRow.isDeleted || ownRow.managedObjectContext == nil)
        #expect(!practicing.isDeleted)
        #expect(fixture.rows(fixture.ada).count == 1)
    }

    @Test("Remove Plan returns her promoted year-plan entry and leaves a classmate's promoted")
    func removePlanReturnsEntries() throws {
        let fixture = try makeFixture()
        fixture.viewModel.toggleScheduled(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        fixture.viewModel.toggleScheduled(student: fixture.bruno, lesson: fixture.lesson, context: fixture.context)
        let plan = try #require(fixture.assignments().first)
        #expect(Set(plan.studentIDs) == [fixture.ada.cloudKitKey, fixture.bruno.cloudKitKey])
        let adaEntry = try fixture.promotedEntry(fixture.ada, into: plan)
        let brunoEntry = try fixture.promotedEntry(fixture.bruno, into: plan)

        fixture.viewModel.toggleScheduled(student: fixture.ada, lesson: fixture.lesson, context: fixture.context)
        #expect(adaEntry.status == .planned)
        #expect(adaEntry.promotedAssignmentID == nil)
        #expect(brunoEntry.status == .promoted)

        // The last child off deletes the plan, and her entry goes back too.
        fixture.viewModel.toggleScheduled(student: fixture.bruno, lesson: fixture.lesson, context: fixture.context)
        #expect(fixture.assignments().isEmpty)
        #expect(brunoEntry.status == .planned)
        #expect(brunoEntry.promotedAssignmentID == nil)
        #expect(fixture.status(fixture.bruno) == .ready)
    }
}
