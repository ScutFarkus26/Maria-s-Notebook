import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The checklist's clicks, card and ladder steps through the view model over a store
/// (plan, Phase 4). The pure rules are in `ChecklistSelectionRulesTests`.
@Suite("Checklist card and selection")
@MainActor
struct ChecklistCardAndSelectionTests {

    /// Ada, Bruno, Chava; Math › Decimal 0–2 (Decimal 0 ready for everyone) and Fractions 0.
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let chava: CDStudent
        let decimal: [CDLesson]
        let fractions: CDLesson

        func cell(_ student: CDStudent, _ lesson: CDLesson) throws -> CellIdentifier {
            let studentID = try #require(student.id)
            let lessonID = try #require(lesson.id)
            return CellIdentifier(studentID: studentID, lessonID: lessonID)
        }

        func status(_ student: CDStudent, _ lesson: CDLesson) -> ChecklistDisplayStatus? {
            viewModel.state(for: student, lesson: lesson)?.displayStatus
        }

        var studentOrder: [UUID] { viewModel.students.compactMap(\.id) }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let chava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Chava", lastName: "Test")
        let decimal = (0..<3).map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Decimal \(order)", area: "Math", sequence: "Decimal"
            )
            lesson.orderInSequence = Int64(order)
            return lesson
        }
        let fractions = CoreDataTestHelpers.seedLesson(
            in: context, name: "Fractions 0", area: "Math", sequence: "Fractions"
        )
        try context.save()

        let suite = "ChecklistCardAndSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context, ada: ada, bruno: bruno, chava: chava,
            decimal: decimal, fractions: fractions
        )
    }

    @Test("A plain click opens the card and drops the selection; ⌘-click and Shift-click select")
    func clicks() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let order = fixture.studentOrder
        let first = try fixture.cell(fixture.ada, fixture.decimal[0])

        viewModel.handleClick(first, kind: .toggle, studentOrder: order, context: fixture.context)
        #expect(viewModel.selectedCells == [first])
        #expect(viewModel.cardCell == nil)

        let last = try fixture.cell(fixture.chava, fixture.decimal[0])
        viewModel.handleClick(last, kind: .extend, studentOrder: order, context: fixture.context)
        #expect(viewModel.selectedCells.count == 3)
        #expect(viewModel.selectedCellsSameLessonID == fixture.decimal[0].id)
        #expect(viewModel.cursorCell == last)

        viewModel.handleClick(first, kind: .plain, studentOrder: order, context: fixture.context)
        #expect(viewModel.selectedCells.isEmpty)
        #expect(viewModel.cardCell == first)
        #expect(viewModel.cardRecord == ChecklistCardRecord())

        viewModel.perform(.closeCard, on: last, context: fixture.context)
        #expect(viewModel.cardCell == first)
        viewModel.perform(.closeCard, on: first, context: fixture.context)
        #expect(viewModel.cardCell == nil)
    }

    @Test("The iPhone's Select mode makes a tap toggle instead of opening the card")
    func selectModeTapToggles() throws {
        let fixture = try makeFixture()
        let first = try fixture.cell(fixture.bruno, fixture.decimal[0])
        fixture.viewModel.isEditModeActive = true
        fixture.viewModel.perform(.click, on: first, context: fixture.context)
        #expect(fixture.viewModel.selectedCells == [first])
        #expect(fixture.viewModel.cardCell == nil)
    }

    @Test("Select ready picks the lesson's ready children; a drag down a column reaches rows in order")
    func selectReadyAndDrag() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let order = fixture.studentOrder
        let brunoFirst = try fixture.cell(fixture.bruno, fixture.decimal[0])
        viewModel.perform(.markPresented, on: brunoFirst, context: fixture.context)

        let firstID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let chavaID = try #require(fixture.chava.id)
        let adaFirst = try fixture.cell(fixture.ada, fixture.decimal[0])
        let chavaFirst = try fixture.cell(fixture.chava, fixture.decimal[0])
        viewModel.selectReady(in: firstID, studentOrder: order)
        #expect(viewModel.selectedCells == [adaFirst, chavaFirst])
        #expect(viewModel.presentationStudentIDs(for: adaFirst, studentOrder: order) == [adaID, chavaID])

        let adaLast = try fixture.cell(fixture.ada, fixture.decimal[2])
        let adaColumn = Set(try fixture.decimal.map { try fixture.cell(fixture.ada, $0) })
        viewModel.dragSelect(from: adaFirst, to: adaLast, base: [], studentOrder: order)
        #expect(viewModel.selectedCells == adaColumn)
    }

    @Test("Folded bands drop out of the drawing order the cursor and Shift-click walk")
    func drawingOrderSkipsFolds() throws {
        let fixture = try makeFixture()
        let all = fixture.viewModel.displayedLessonIDs
        #expect(all.count == 4)
        let fractionsID = try #require(fixture.fractions.id)
        fixture.viewModel.toggleCollapsed("Decimal")
        #expect(fixture.viewModel.displayedLessonIDs == [fractionsID])
        let layout = fixture.viewModel.rowLayout(metrics: .regular)
        #expect(layout.lessonIDs == [fractionsID])
        // Each band before the Fractions row is 30 pt, the folded Decimal one included.
        let bandsAbove = try #require(fixture.viewModel.visibleSequences.firstIndex(of: "Fractions")) + 1
        #expect(layout.top(of: fractionsID) == CGFloat(bandsAbove) * 30)
    }

    @Test("Presented only moves a child up: a second press leaves her presented")
    func markPresentedNeverUndoes() throws {
        let fixture = try makeFixture()
        let cell = try fixture.cell(fixture.ada, fixture.decimal[0])
        fixture.viewModel.perform(.markPresented, on: cell, context: fixture.context)
        #expect(fixture.status(fixture.ada, fixture.decimal[0]) == .presented)
        fixture.viewModel.perform(.markPresented, on: cell, context: fixture.context)
        #expect(fixture.status(fixture.ada, fixture.decimal[0]) == .presented)
    }

    @Test("Practicing opens work (presenting first), Reviewing moves it to review")
    func practiceAndReview() throws {
        let fixture = try makeFixture()
        let cell = try fixture.cell(fixture.chava, fixture.decimal[1])
        fixture.viewModel.perform(.markPracticing, on: cell, context: fixture.context)
        #expect(fixture.status(fixture.chava, fixture.decimal[1]) == .practicing)
        #expect(fixture.viewModel.state(for: fixture.chava, lesson: fixture.decimal[1])?.isPresented == true)

        fixture.viewModel.perform(.markReviewing, on: cell, context: fixture.context)
        #expect(fixture.status(fixture.chava, fixture.decimal[1]) == .reviewing)

        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", try #require(fixture.decimal[1].id).uuidString)
        let works = fixture.context.safeFetch(request)
        #expect(works.count == 1)
        #expect(works.first?.status == .review)
    }

    @Test("Opening the card reads the presented date; a change from the card refreshes it")
    func cardRecordFollowsChanges() throws {
        let fixture = try makeFixture()
        let cell = try fixture.cell(fixture.ada, fixture.decimal[0])
        fixture.viewModel.openCard(cell, context: fixture.context)
        #expect(fixture.viewModel.cardRecord.presentedOn == nil)

        fixture.viewModel.perform(.markPresented, on: cell, context: fixture.context)
        let presentedOn = try #require(fixture.viewModel.cardRecord.presentedOn)
        #expect(presentedOn.isSameDay(as: Date()))
    }

    @Test("A draft for the present sheet holds exactly the children asked for; unused, it goes again")
    func presentationDraft() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let chavaID = try #require(fixture.chava.id)
        let ids = [adaID, chavaID]
        let draft = try #require(fixture.viewModel.makePresentationDraft(
            lessonID: lessonID, studentIDs: ids, context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        #expect(Set(draft.studentIDs) == Set(ids.map(\.uuidString)))
        #expect(draft.lessonID == lessonID.uuidString)
        #expect(!draft.isPresented)

        fixture.viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        #expect(fixture.context.safeFetch(request).isEmpty)
    }

    @Test("A recorded draft stays when the sheet closes")
    func recordedDraftStays() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let draft = try #require(fixture.viewModel.makePresentationDraft(
            lessonID: lessonID, studentIDs: [adaID], context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        draft.markPresented(at: Date())
        fixture.context.safeSave()

        fixture.viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        #expect(!draft.isDeleted)
        #expect(draft.managedObjectContext != nil)
    }

    @Test("A draft the sheet saved to the Inbox stays when the sheet closes")
    func savedDraftStays() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let draft = try #require(fixture.viewModel.makePresentationDraft(
            lessonID: lessonID, studentIDs: [adaID], context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        // The sheet's Save with no date: the draft stays unscheduled, but written.
        draft.unschedule()
        fixture.context.safeSave()
        #expect(!draft.isScheduled)

        fixture.viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        #expect(!draft.isDeleted)
        #expect(draft.managedObjectContext != nil)
    }

    @Test("A draft with notes typed on it stays when the sheet closes")
    func notedDraftStays() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let draft = try #require(fixture.viewModel.makePresentationDraft(
            lessonID: lessonID, studentIDs: [adaID], context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        #expect(asMade.matches(draft))
        draft.notes = "Bring the golden beads"
        fixture.context.safeSave()

        fixture.viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        #expect(!draft.isDeleted)
        #expect(draft.notes == "Bring the golden beads")
    }
}
