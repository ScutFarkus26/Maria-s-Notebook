import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Maya S and Eli P; Math › Decimal 0, then Decimal 1; the Checklist's view model over them.
/// Shared by the 11-03 C suites.
@MainActor
struct ChecklistFix1103CFixture {
    let viewModel: ClassAreaChecklistViewModel
    let context: NSManagedObjectContext
    let maya: CDStudent
    let eli: CDStudent
    let first: CDLesson
    let second: CDLesson

    var firstID: String { first.id?.uuidString ?? "" }

    static func make(context: NSManagedObjectContext? = nil) throws -> ChecklistFix1103CFixture {
        let context = try context ?? CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal 0", area: "Math", sequence: "Decimal")
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal 1", area: "Math", sequence: "Decimal")
        second.orderInSequence = 1
        try context.save()

        let viewModel = ClassAreaChecklistViewModel()
        let suite = "ChecklistFix1103CTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        let fixture = ChecklistFix1103CFixture(
            viewModel: viewModel, context: context, maya: maya, eli: eli, first: first, second: second
        )
        fixture.viewModel.loadData(context: context)
        fixture.viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return fixture
    }

    func cell(_ student: CDStudent, _ lesson: CDLesson) throws -> CellIdentifier {
        CellIdentifier(studentID: try #require(student.id), lessonID: try #require(lesson.id))
    }

    func status(_ student: CDStudent, _ lesson: CDLesson) -> ChecklistDisplayStatus? {
        viewModel.state(for: student, lesson: lesson)?.displayStatus
    }

    /// Every presentation of `lesson` naming the child, pending changes included.
    func assignments(_ student: CDStudent, _ lesson: CDLesson) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lesson.id?.uuidString ?? "")
        return context.safeFetch(request).filter { !$0.isDeleted && $0.studentIDs.contains(student.cloudKitKey) }
    }

    /// A given presentation of the first lesson, on `day`.
    @discardableResult
    func give(_ students: [CDStudent], on day: String, confirming: [CDStudent] = []) throws -> CDLessonAssignment {
        let given = CDLessonAssignment(context: context)
        given.lessonID = firstID
        given.studentIDs = students.map(\.cloudKitKey)
        given.markPresented(at: try CoreDataTestHelpers.day(day), snapshotLesson: false)
        for student in confirming {
            given.confirmStudent(try #require(student.id))
        }
        return given
    }

    /// Her history row for `presentation`, dated as it was given.
    @discardableResult
    func historyRow(_ student: CDStudent, for presentation: CDLessonAssignment) -> CDLessonPresentation {
        let row = CDLessonPresentation(context: context)
        row.studentID = student.cloudKitKey
        row.lessonID = presentation.lessonID
        row.presentationID = presentation.id?.uuidString
        row.state = .presented
        row.presentedAt = presentation.presentedAt
        return row
    }

    /// A year-plan entry for the first lesson, promoted into `plan`.
    func promotedEntry(_ student: CDStudent, into plan: CDLessonAssignment) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.cloudKitKey
        entry.lessonID = firstID
        entry.plannedDate = plan.scheduledFor
        entry.sequenceGroupKey = "Math::Decimal"
        entry.status = .promoted
        entry.promotedAssignmentID = plan.id?.uuidString
        return entry
    }
}

/// Bug hunt 2026-11-03, the Checklist's marks and removals (#2, #4, #8, #10): its
/// marks do what the presentation sheet's do, its removals keep notes, and its
/// selection's Add to Inbox only adds.
@Suite("Checklist marks and removals (11-03 C)")
@MainActor
struct ChecklistFix1103CTests {

    typealias Fixture = ChecklistFix1103CFixture

    // MARK: - #2 Removals keep the notes

    @Test("#2: Unmark Presented on a one-child given presentation keeps its notes as hers")
    func unmarkKeepsNotes() throws {
        let fixture = try Fixture.make()
        let given = try fixture.give([fixture.maya], on: "2026-10-20")
        let classNote = CDNote(context: fixture.context)
        classNote.body = "Counted to a hundred on her own."
        classNote.scope = .all
        classNote.lessonAssignment = given
        let row = fixture.historyRow(fixture.maya, for: given)
        row.followUpNote = "Check her teen board work."
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.togglePresented(student: fixture.maya, lesson: fixture.first, context: fixture.context)

        let mayaID = try #require(fixture.maya.id)
        #expect(given.isDeleted || given.managedObjectContext == nil)
        #expect(!classNote.isDeleted && classNote.managedObjectContext != nil)
        #expect(classNote.lessonAssignment == nil)
        #expect(classNote.scope == .student(mayaID))
        #expect(classNote.lessonID == fixture.firstID)
        // The history row's follow-up note goes with the row, so its text is kept as a note on her.
        let kept = fixture.context.safeFetch(CDFetchRequest(CDNote.self))
            .filter { $0.body.contains("teen board") }
        #expect(kept.count == 1)
        #expect(kept.first?.scope == .student(mayaID))
        #expect(kept.first?.lessonID == fixture.firstID)
    }

    @Test("#2: Remove Plan on her own plan keeps its notes as hers")
    func removePlanKeepsNotes() throws {
        let fixture = try Fixture.make()
        let plan = PresentationFactory.makeDraft(
            lesson: fixture.first, students: [fixture.maya], context: fixture.context
        )
        let note = CDNote(context: fixture.context)
        note.body = "Use the golden beads, not the cards."
        note.scope = .student(try #require(fixture.maya.id))
        note.lessonAssignment = plan
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.toggleScheduled(student: fixture.maya, lesson: fixture.first, context: fixture.context)

        #expect(plan.isDeleted || plan.managedObjectContext == nil)
        #expect(!note.isDeleted && note.managedObjectContext != nil)
        #expect(note.lessonAssignment == nil)
        #expect(note.lessonID == fixture.firstID)
    }

    @Test("#2: a one-child given presentation isn't taken off from the menu without asking")
    func unmarkFromTheMenuWaits() throws {
        let fixture = try Fixture.make()
        let given = try fixture.give([fixture.maya], on: "2026-10-20")
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .togglePresented, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(!given.isDeleted && given.managedObjectContext != nil)
        #expect(fixture.status(fixture.maya, fixture.first) == .presented)
    }

    // MARK: - #4 A mark releases her from the plan her year plan put her on

    enum Mark: String, CaseIterable, CustomTestStringConvertible {
        case cellPresented, cellToggle, cellPracticing, cellMastered
        case batchPresented, batchPreviously, batchMastered

        var testDescription: String { rawValue }
    }

    @Test("#4: every Checklist mark that records a presentation releases her from Thursday's plan",
          arguments: Mark.allCases)
    func markReleasesPlan(_ mark: Mark) throws {
        let fixture = try Fixture.make()
        let thursday = PresentationFactory.makeScheduled(
            lesson: fixture.first, students: [fixture.maya, fixture.eli],
            scheduledFor: Date().addingTimeInterval(3 * 86_400), context: fixture.context
        )
        let entry = fixture.promotedEntry(fixture.maya, into: thursday)
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)
        let cell = try fixture.cell(fixture.maya, fixture.first)

        switch mark {
        case .cellPresented: fixture.viewModel.perform(.markPresented, on: cell, context: fixture.context)
        case .cellToggle: fixture.viewModel.perform(.togglePresented, on: cell, context: fixture.context)
        case .cellPracticing: fixture.viewModel.perform(.markPracticing, on: cell, context: fixture.context)
        case .cellMastered: fixture.viewModel.perform(.markComplete, on: cell, context: fixture.context)
        case .batchPresented:
            fixture.viewModel.selectedCells = [cell]
            fixture.viewModel.batchMarkPresented(context: fixture.context)
        case .batchPreviously:
            fixture.viewModel.selectedCells = [cell]
            fixture.viewModel.batchMarkPreviouslyPresented(context: fixture.context)
        case .batchMastered:
            fixture.viewModel.selectedCells = [cell]
            fixture.viewModel.batchMarkProficient(context: fixture.context)
        }

        #expect(thursday.studentIDs == [fixture.eli.cloudKitKey])
        let given = try #require(fixture.assignments(fixture.maya, fixture.first).first { $0.isPresented })
        #expect(entry.promotedAssignmentID == given.id?.uuidString)
    }

    @Test("#4: joining a classmate's undated record releases only her, not the classmate's re-give plan")
    func sharedUndatedRecordReleasesOnlyHer() throws {
        let fixture = try Fixture.make()
        let eliID = try #require(fixture.eli.id)
        _ = PresentationFactory.makePreviouslyPresented(
            lessonID: try #require(fixture.first.id), studentIDs: [eliID], context: fixture.context
        )
        // Eli is down for a re-give on Thursday through his year plan.
        let thursday = PresentationFactory.makeScheduled(
            lesson: fixture.first, students: [fixture.eli],
            scheduledFor: Date().addingTimeInterval(3 * 86_400), context: fixture.context
        )
        let entry = fixture.promotedEntry(fixture.eli, into: thursday)
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.selectedCells = [try fixture.cell(fixture.maya, fixture.first)]
        fixture.viewModel.batchMarkPreviouslyPresented(context: fixture.context)

        #expect(!thursday.isDeleted && thursday.managedObjectContext != nil)
        #expect(thursday.studentIDs == [fixture.eli.cloudKitKey])
        #expect(entry.promotedAssignmentID == thursday.id?.uuidString)
    }

    // MARK: - #8 No presentation means an undated one

    @Test("#8: Mastered, Practicing or Reviewing with no presentation attaches an undated one",
          arguments: [ChecklistCellAction.markComplete, .markPracticing, .markReviewing])
    func cellMarkAttachesUndated(_ action: ChecklistCellAction) throws {
        let fixture = try Fixture.make()
        fixture.viewModel.perform(action, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context)

        let given = fixture.assignments(fixture.maya, fixture.first).filter(\.isPresented)
        #expect(given.count == 1)
        #expect(given.allSatisfy { $0.presentedAt == nil })
        // Her history row doesn't say she was given it today either.
        let rows = try historyRows(fixture, fixture.maya)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.presentedAt == nil })
    }

    private func historyRows(_ fixture: Fixture, _ student: CDStudent) throws -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@", student.cloudKitKey, fixture.firstID
        )
        return fixture.context.safeFetch(request).filter { !$0.isDeleted }
    }

    @Test("#8: the selection's Mastered with no presentation attaches an undated one")
    func batchMasteredAttachesUndated() throws {
        let fixture = try Fixture.make()
        fixture.viewModel.selectedCells = [
            try fixture.cell(fixture.maya, fixture.first), try fixture.cell(fixture.eli, fixture.first)
        ]
        fixture.viewModel.batchMarkProficient(context: fixture.context)

        for student in [fixture.maya, fixture.eli] {
            let given = fixture.assignments(student, fixture.first).filter(\.isPresented)
            #expect(given.count == 1)
            #expect(given.allSatisfy { $0.presentedAt == nil })
            #expect(try historyRows(fixture, student).allSatisfy { $0.presentedAt == nil })
            #expect(fixture.status(student, fixture.first) == .mastered)
        }
    }

    @Test("#8: Mastered on a lesson she was given keeps that presentation and adds none")
    func masteredKeepsGivenPresentation() throws {
        let fixture = try Fixture.make()
        let given = try fixture.give([fixture.maya], on: "2026-10-20")
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)

        fixture.viewModel.perform(
            .markComplete, on: try fixture.cell(fixture.maya, fixture.first), context: fixture.context
        )

        #expect(fixture.assignments(fixture.maya, fixture.first).map(\.objectID) == [given.objectID])
    }

    // MARK: - #10 Add to Inbox on a selection only adds

    @Test("#10: Add to Inbox on a stale selection never takes her off a plan made since")
    func batchInboxOnlyAdds() throws {
        let fixture = try Fixture.make()
        // Planned on another device after the grid was drawn.
        let thursday = PresentationFactory.makeScheduled(
            lesson: fixture.first, students: [fixture.maya],
            scheduledFor: Date().addingTimeInterval(3 * 86_400), context: fixture.context
        )
        try fixture.context.save()
        #expect(fixture.status(fixture.maya, fixture.first) == .ready)

        fixture.viewModel.selectedCells = [
            try fixture.cell(fixture.maya, fixture.first), try fixture.cell(fixture.eli, fixture.first)
        ]
        fixture.viewModel.batchAddToInbox(context: fixture.context)

        #expect(!thursday.isDeleted && thursday.managedObjectContext != nil)
        #expect(thursday.studentIDs == [fixture.maya.cloudKitKey])
        #expect(fixture.assignments(fixture.maya, fixture.first).map(\.objectID) == [thursday.objectID])
        // Eli, on nothing, goes on the Inbox.
        let eliPlans = fixture.assignments(fixture.eli, fixture.first)
        #expect(eliPlans.count == 1)
        #expect(eliPlans.first?.scheduledFor == nil)
    }
}
