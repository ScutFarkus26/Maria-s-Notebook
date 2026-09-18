import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Presentation Record Index")
@MainActor
struct PresentationRecordIndexTests {
    private typealias Given = PresentationRecordIndex.Given

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    /// Three children and two lessons:
    /// - Ora: Checkerboard given twice (a row and a presented assignment on
    ///   different days), confirmed ready on the second; Bells mastered by row.
    /// - Etty: Checkerboard on an unpresented draft with Dalia; a planned
    ///   year-plan entry for Bells.
    /// - Dalia: on that draft; a skipped entry for Bells; an undated
    ///   "previously presented" mark for Bells.
    private struct Classroom {
        let checkerboard: CDLesson
        let bells: CDLesson
        let ora: CDStudent
        let etty: CDStudent
        let dalia: CDStudent
        let secondPass: CDLessonAssignment
    }

    private func seed(in context: NSManagedObjectContext) throws -> Classroom {
        let checkerboard = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let bells = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let dalia = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth")
        CoreDataTestHelpers.save(context)

        let oraID = try #require(ora.id).uuidString
        let daliaID = try #require(dalia.id).uuidString
        let checkerboardID = try #require(checkerboard.id).uuidString
        let bellsID = try #require(bells.id).uuidString

        let firstRow = CDLessonPresentation(context: context)
        firstRow.studentID = oraID
        firstRow.lessonID = checkerboardID
        firstRow.presentedAt = try day("2026-03-11")

        _ = PresentationFactory.makePresented(
            lesson: checkerboard, students: [ora], presentedAt: try day("2026-03-11"), context: context
        )
        let secondPass = PresentationFactory.makePresented(
            lesson: checkerboard, students: [ora], presentedAt: try day("2026-05-02"), context: context
        )
        secondPass.confirmStudent(try #require(ora.id))

        let bellsRow = CDLessonPresentation(context: context)
        bellsRow.studentID = oraID
        bellsRow.lessonID = bellsID
        bellsRow.presentedAt = try day("2026-01-20")
        bellsRow.masteredAt = try day("2026-02-10")

        _ = PresentationFactory.makeDraft(lesson: checkerboard, students: [etty, dalia], context: context)

        let planned = CDYearPlanEntry(context: context)
        planned.studentID = try #require(etty.id).uuidString
        planned.lessonID = bellsID
        let skipped = CDYearPlanEntry(context: context)
        skipped.studentID = daliaID
        skipped.lessonID = bellsID
        skipped.statusRaw = YearPlanEntryStatus.skipped.rawValue

        _ = PresentationFactory.makePreviouslyPresented(
            lessonID: try #require(bells.id), studentIDs: [try #require(dalia.id)], context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(
            checkerboard: checkerboard, bells: bells, ora: ora, etty: etty, dalia: dalia, secondPass: secondPass
        )
    }

    @Test("Given folds rows and presented assignments into one day list, with mastery and confirmation")
    func givenFoldsRowsAndAssignments() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let classroom = try seed(in: context)
        let index = PresentationRecordIndex(in: context)
        let oraID = try #require(classroom.ora.id).uuidString
        let checkerboardID = try #require(classroom.checkerboard.id).uuidString
        let bellsID = try #require(classroom.bells.id).uuidString

        let checkerboard = try #require(index.given(student: oraID, lesson: checkerboardID))
        #expect(checkerboard.days == [try day("2026-03-11"), try day("2026-05-02")])
        #expect(checkerboard.confirmed)
        #expect(!checkerboard.mastered)

        let bells = try #require(index.given(student: oraID, lesson: bellsID))
        #expect(bells.mastered)
        #expect(!bells.confirmed)
        #expect(bells.days == [try day("2026-01-20")])

        #expect(index.givenByStudent[oraID]?.keys.sorted() == [bellsID, checkerboardID].sorted())
        #expect(index.masteredStudents(lesson: bellsID) == [oraID])
        #expect(index.confirmedStudents(lesson: checkerboardID) == [oraID])
        #expect(index.latestPresentedAssignmentByLesson[checkerboardID]?[oraID] == classroom.secondPass.objectID)
    }

    @Test("Standing puts the record ahead of the plan and reads skipped entries as no plan")
    func standingOrdersRecordPlanNothing() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let classroom = try seed(in: context)
        let index = PresentationRecordIndex(in: context)
        let ettyID = try #require(classroom.etty.id).uuidString
        let daliaID = try #require(classroom.dalia.id).uuidString
        let checkerboardID = try #require(classroom.checkerboard.id).uuidString
        let bellsID = try #require(classroom.bells.id).uuidString

        #expect(index.standing(student: ettyID, lesson: checkerboardID) == .planned)
        #expect(index.standing(student: daliaID, lesson: checkerboardID) == .planned)
        #expect(index.standing(student: ettyID, lesson: bellsID) == .planned)
        #expect(index.openPlanByLesson[checkerboardID] == [ettyID, daliaID])

        // An undated mark is still on record, with no days to show.
        #expect(index.standing(student: daliaID, lesson: bellsID) == .onRecord(Given()))
        #expect(index.givenStudents(lesson: bellsID).contains(daliaID))
        #expect(index.standing(student: "nobody", lesson: bellsID) == .noRecord)
    }

    @Test("A scoped index matches the unscoped one for its lessons and children")
    func scopedMatchesUnscoped() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let classroom = try seed(in: context)
        let oraID = try #require(classroom.ora.id).uuidString
        let checkerboardID = try #require(classroom.checkerboard.id).uuidString
        let bellsID = try #require(classroom.bells.id).uuidString

        let whole = PresentationRecordIndex(in: context)
        let scoped = PresentationRecordIndex(lessonIDs: [checkerboardID], students: [oraID], in: context)

        #expect(scoped.givenByLesson[checkerboardID]?[oraID] == whole.givenByLesson[checkerboardID]?[oraID])
        #expect(scoped.givenByLesson[bellsID] == nil)
        #expect(scoped.openPlanByLesson[checkerboardID] == nil)
        #expect(scoped.givenByStudent.keys.sorted() == [oraID])
    }
}
