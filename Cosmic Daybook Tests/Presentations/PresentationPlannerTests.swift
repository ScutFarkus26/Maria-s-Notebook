import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Planning a lesson from a picker. The draft is the easy half; the half that
/// matters is what a repeat writes down — the same two things the MCP regive
/// guard writes, because it is the same code.
@Suite("Presentation Planner")
@MainActor
struct PresentationPlannerTests {

    private struct Fixture {
        let checkerboard: CDLesson
        let ora: CDStudent
        let etty: CDStudent
        /// Ora's Checkerboard on 2026-03-11.
        let prior: CDLessonAssignment
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    private func seed(in context: NSManagedObjectContext) throws -> Fixture {
        let checkerboard = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let prior = PresentationFactory.makePresented(
            lesson: checkerboard, students: [ora], presentedAt: try day("2026-03-11"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return Fixture(checkerboard: checkerboard, ora: ora, etty: etty, prior: prior)
    }

    // MARK: - A second pass

    @Test("A second pass flags her earlier record and opens the draft with the purpose line")
    func secondPassFlagsAndAnnotates() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)
        let planned = try day("2026-04-02")

        let draft = try #require(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard,
            students: [fixture.ora, fixture.etty],
            purpose: .secondPass,
            plannedOn: planned,
            in: context
        ))

        #expect(fixture.prior.needsAnotherPresentation)
        #expect(draft.notes.hasPrefix(RepeatPurpose.secondPass.noteLine(plannedOn: planned)))
        #expect(RepeatPurpose.parse(notes: draft.notes) == .secondPass)
        #expect(draft.state == .draft)
        #expect(Set(draft.studentIDs) == Set([fixture.ora, fixture.etty].compactMap { $0.id?.uuidString }))
    }

    @Test("A review writes its line and flags nothing")
    func reviewAnnotatesWithoutFlagging() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)
        let planned = try day("2026-04-02")

        let draft = try #require(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard,
            students: [fixture.ora],
            purpose: .review,
            plannedOn: planned,
            in: context
        ))

        #expect(!fixture.prior.needsAnotherPresentation)
        #expect(draft.notes.hasPrefix(RepeatPurpose.review.noteLine(plannedOn: planned)))
    }

    // MARK: - No purpose

    @Test("No purpose flags nothing and writes no note, however the record reads")
    func noPurposeLeavesTheRecordAlone() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)

        let draft = try #require(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard,
            students: [fixture.ora],
            purpose: nil,
            plannedOn: try day("2026-04-02"),
            in: context
        ))

        #expect(!fixture.prior.needsAnotherPresentation)
        #expect(draft.notes.isEmpty)
        #expect(RepeatPurpose.parse(notes: draft.notes) == nil)
    }

    @Test("A second pass for a child nobody has on record flags nothing but still says why")
    func secondPassForANewcomer() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)
        let planned = try day("2026-04-02")

        let draft = try #require(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard,
            students: [fixture.etty],
            purpose: .secondPass,
            plannedOn: planned,
            in: context
        ))

        #expect(!fixture.prior.needsAnotherPresentation)
        #expect(draft.notes.hasPrefix(RepeatPurpose.secondPass.noteLine(plannedOn: planned)))
    }

    @Test("Nobody to plan for is no draft at all")
    func emptyRosterPlansNothing() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)

        #expect(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard, students: [], purpose: nil, in: context
        ) == nil)
        #expect(PresentationPlanner.planDraft(
            lesson: fixture.checkerboard, studentIDs: [], purpose: nil, in: context
        ) == nil)
    }

    // MARK: - Reading the record for a picker

    @Test("The picker's conflict list is the children the record already covers")
    func conflictsNameTheChildrenOnRecord() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)
        let lessonID = try #require(fixture.checkerboard.id).uuidString
        let index = PresentationRecordIndex(lessonIDs: [lessonID], in: context)

        let conflicts = PresentationPlanner.repeatConflicts(
            lesson: fixture.checkerboard,
            students: [fixture.ora, fixture.etty],
            on: try day("2026-04-02"),
            index: index
        )

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.student.id == fixture.ora.id)
        #expect(conflicts.first?.days == [AppCalendar.startOfDay(try day("2026-03-11"))])
    }
}
