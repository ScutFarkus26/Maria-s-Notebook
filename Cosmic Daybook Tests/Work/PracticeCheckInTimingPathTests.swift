import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The lesson-loop gaps of plan "Tide list clean-up 2026-11", Phase 2, at the
/// timing rules themselves: filing again keeps the check-ins already there,
/// and the planning paths that didn't yet bring practice forward (merging two
/// presentations, moving a child into a planned group, scheduling a Parsha
/// lesson) now do.
///
/// The planning paths read the wall clock, so their days are in 2030, far
/// past "never before today".
@Suite("Practice check-in timing: filing again and the other planning paths")
@MainActor
struct PracticeCheckInTimingPathTests {

    let ada = UUID()
    let ben = UUID()

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    private func lesson(_ name: String, step: Int, in context: NSManagedObjectContext) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: "Addition")
        lesson.id = UUID()
        lesson.orderInSequence = Int64(step)
        return lesson
    }

    private func students(in context: NSManagedObjectContext) -> (ada: CDStudent, ben: CDStudent) {
        let first = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        first.id = ada
        let second = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross")
        second.id = ben
        return (first, second)
    }

    /// Ada's open practice on `lesson`, set on Friday 2026-11-20, checked on
    /// Monday 2030-01-21.
    private func practice(
        on lesson: CDLesson, presentationID: UUID? = nil, in context: NSManagedObjectContext
    ) throws -> (work: CDWorkModel, checkIn: CDWorkCheckIn) {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: ada, lessonID: try #require(lesson.id)
        )
        work.id = UUID()
        work.status = .active
        work.assignedAt = try day("2026-11-20")
        work.createdAt = work.assignedAt
        if let presentationID { work.presentationID = presentationID.uuidString }
        let checkIn = CDWorkCheckIn.make(for: work, on: try day("2030-01-21"), in: context)
        return (work, checkIn)
    }

    private func checkDay(_ checkIn: CDWorkCheckIn) -> Date? {
        checkIn.date.map(AppCalendar.startOfDay)
    }

    // MARK: - Filing the same lesson again

    @Test("Filing again keeps a check-in the guide moved later")
    func filingAgainKeepsAMovedCheckIn() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let presentationID = UUID()
        let (work, movedLater) = try practice(on: first, presentationID: presentationID, in: context)

        let made = PracticeCheckInTiming.scheduleCheckIns(
            forWorkFrom: presentationID, on: [ada: try day("2030-01-14")], in: context
        )
        #expect(made == 0)
        #expect(checkDay(movedLater) == (try day("2030-01-21")), "where the guide put it")
        #expect(WorkLogService.checkIns(of: work, in: context).count == 1)
    }

    @Test("Filing again adds nothing after a check-in already done")
    func filingAgainAddsNothingAfterADoneOne() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let presentationID = UUID()
        let (work, done) = try practice(on: first, presentationID: presentationID, in: context)
        done.status = .completed

        let made = PracticeCheckInTiming.scheduleCheckIns(
            forWorkFrom: presentationID, on: [ada: try day("2030-01-14")], in: context
        )
        #expect(made == 0)
        #expect(WorkLogService.scheduledCheckIns(of: work, in: context).isEmpty)
    }

    // MARK: - The other planning paths

    @Test("Merging her plan into one on a day brings her earlier practice forward")
    func mergeBringsPracticeForward() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let (adaStudent, benStudent) = students(in: context)
        let (_, checkIn) = try practice(on: first, in: context)
        let hers = PresentationFactory.makeDraft(lesson: second, students: [adaStudent], context: context)
        let thursday = PresentationFactory.makeDraft(lesson: second, students: [benStudent], context: context)
        thursday.schedule(onDay: try day("2030-01-10"))

        let merged = PresentationMergeService.merge(
            sourceID: try #require(hers.id), targetID: try #require(thursday.id), context: context
        )
        #expect(merged)
        #expect(checkDay(checkIn) == (try day("2030-01-09")), "the school day before the merged plan")
    }

    @Test("Moving her into a planned group brings her earlier practice forward")
    func groupMoveBringsPracticeForward() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let (adaStudent, benStudent) = students(in: context)
        let cyrus = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cyrus", lastName: "Hale")
        cyrus.id = UUID()
        let (_, checkIn) = try practice(on: first, in: context)
        let unplaced = PresentationFactory.makeDraft(
            lesson: second, students: [adaStudent, benStudent], context: context
        )
        let thursday = PresentationFactory.makeDraft(lesson: second, students: [cyrus], context: context)
        thursday.schedule(onDay: try day("2030-01-10"))

        let receipt = PresentationGroupMove.move(ada, from: unplaced, to: thursday, in: context)
        #expect(receipt != nil)
        #expect(checkDay(checkIn) == (try day("2030-01-09")))
    }

    @Test("Scheduling a Parsha lesson on a day brings earlier practice forward; the Inbox moves nothing")
    func parshaPlanBringsPracticeForward() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let (adaStudent, _) = students(in: context)
        let (_, checkIn) = try practice(on: first, in: context)

        ScheduleParshaLessonSheet.addPlan(lesson: second, students: [adaStudent], scheduledFor: nil, context: context)
        #expect(checkDay(checkIn) == (try day("2030-01-21")), "a plan with no day times nothing")

        let plan = ScheduleParshaLessonSheet.addPlan(
            lesson: second, students: [adaStudent], scheduledFor: try day("2030-01-10"), context: context
        )
        #expect(plan.scheduledFor.map(AppCalendar.startOfDay) == (try day("2030-01-10")))
        #expect(checkDay(checkIn) == (try day("2030-01-09")))
    }
}
