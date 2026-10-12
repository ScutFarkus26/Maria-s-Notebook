import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Planning a lesson for children already waiting for it (bug hunt
/// 2026-10-12, #32): the class map's Plan and the Plan Presentation sheet's
/// paths reuse the waiting plan rather than stacking a second draft. And the
/// "had this" caption drops the year by school year, not calendar year (#51).
@Suite("Presentations fixes 2026-10-12: plans already waiting")
@MainActor
struct PresentationPlanCheckFix1012Pr {

    private struct Classroom {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let ora: CDStudent
        let etty: CDStudent
    }

    private func seed() throws -> Classroom {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(context: context, lesson: lesson, ora: ora, etty: etty)
    }

    private func assignments(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    @Test("Planning a child already on a waiting draft opens that draft and makes none")
    func reusesTheWaitingDraft() throws {
        let classroom = try seed()
        let waiting = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora, classroom.etty], context: classroom.context
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        let result = try #require(PresentationPlanner.planOrReuse(
            lesson: classroom.lesson, students: [classroom.ora], purpose: nil, in: classroom.context
        ))

        #expect(result.plan == waiting)
        #expect(!result.isNew)
        #expect(assignments(in: classroom.context).count == 1)
    }

    @Test("A scheduled plan counts as waiting too")
    func reusesAScheduledPlan() throws {
        let classroom = try seed()
        let scheduled = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora], context: classroom.context
        )
        scheduled.schedule(for: try CoreDataTestHelpers.day("2026-10-14"), using: AppCalendar.shared)
        #expect(CoreDataTestHelpers.save(classroom.context))

        let result = try #require(PresentationPlanner.planOrReuse(
            lesson: classroom.lesson, students: [classroom.ora], purpose: nil, in: classroom.context
        ))

        #expect(result.plan == scheduled)
        #expect(assignments(in: classroom.context).count == 1)
    }

    @Test("Only the children no plan names yet go on the new draft")
    func newDraftLeavesOutThePlanned() throws {
        let classroom = try seed()
        _ = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora], context: classroom.context
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        let result = try #require(PresentationPlanner.planOrReuse(
            lesson: classroom.lesson, students: [classroom.ora, classroom.etty], purpose: nil,
            in: classroom.context
        ))

        #expect(result.isNew)
        #expect(result.plan.resolvedStudentIDs == [try #require(classroom.etty.id)])
        #expect(assignments(in: classroom.context).count == 2)
    }

    @Test("A lesson already given is a record, not a waiting plan")
    func givenRecordIsNotAPlan() throws {
        let classroom = try seed()
        _ = PresentationFactory.makePresented(
            lesson: classroom.lesson, students: [classroom.ora],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: classroom.context
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        let result = try #require(PresentationPlanner.planOrReuse(
            lesson: classroom.lesson, students: [classroom.ora], purpose: nil, in: classroom.context
        ))

        #expect(result.isNew)
        #expect(assignments(in: classroom.context).count == 2)
    }

    // MARK: - The caption's year (#51)

    @Test("A lesson from last school year keeps its year though it is this calendar year")
    func lastSchoolYearKeepsTheYear() throws {
        // September, after the year started: March was last school year.
        let now = try CoreDataTestHelpers.day("2026-09-15")
        let march = try CoreDataTestHelpers.day("2026-03-11")
        #expect(StudentRecordCaption.text(for: .init(days: [march]), now: now)
            == "had this \(DateFormatters.mediumDate.string(from: march))")
    }

    @Test("A lesson from this school year drops the year though it was last calendar year")
    func thisSchoolYearDropsTheYear() throws {
        // January: September was this school year.
        let now = try CoreDataTestHelpers.day("2027-01-10")
        let september = try CoreDataTestHelpers.day("2026-09-20")
        #expect(StudentRecordCaption.text(for: .init(days: [september]), now: now)
            == "had this \(DateFormatters.shortMonthDay.string(from: september))")
    }
}
