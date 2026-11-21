import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic review 2026-11-20, the work rules (plan "Domain logic fixes",
// Phase 5): the due date and the next check are two things (R4), a check is
// done one way (R11), one clock says how long work has gone quiet (R13),
// practice needs a finished check-in and a resolved presentation (R14), and
// open means the status (R23). Each of these failed before the fix.

@Suite("Work rules (domain logic, Phase 5)")
@MainActor
struct WorkRulesTests {
    private typealias Fixture = CheckInFixture

    func day(_ offset: Int) -> Date {
        AppCalendar.addingDays(offset, to: AppCalendar.startOfDay(Date()))
    }

    // MARK: - R4: the due date and the next check

    @Test("Logged work leaves Attention: the check day is no longer its due date")
    func loggedWorkLeavesAttention() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        let monday = day(-3)
        WorkCheckInService(context: context).scheduleCheck(for: work, on: monday)
        #expect(CoreDataTestHelpers.save(context))
        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) == .attention, "the check is due")

        // Keep working: seen, unchanged.
        try WorkLogService.log([.init(work: work)], on: monday, context: context)

        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) != .attention)
    }

    @Test("Scheduling a check leaves the guide's due date alone")
    func schedulingKeepsTheDueDate() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster")
        let friday = day(9)
        work.dueAt = friday

        WorkCheckInService(context: context).scheduleCheck(for: work, on: day(7))
        WorkCheckInService(context: context).scheduleCheck(for: work, on: day(8))

        #expect(work.dueAt == friday)
    }

    // MARK: - R11: the check happened

    @Test("Claude's complete_check_in_on settles an earlier missed check too")
    func checkDoneSettlesEarlierMissedCheck() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])
        // The fixture's check-in is on 2026-09-18; one two days earlier was missed.
        let later = try #require(WorkLogService.scheduledCheckIns(of: work, in: context).first)
        let laterDay = try #require(later.date)
        let missed = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(-2, to: laterDay), in: context)
        #expect(CoreDataTestHelpers.save(context))

        _ = try await Fixture.tool(named: "update_work", in: tools).handler([
            "work_id": .string(try Fixture.id(of: work)),
            "complete_check_in_on": .string("2026-09-18")
        ])

        #expect(later.status == .completed)
        #expect(missed.status == .completed, "the missed check is settled, so the work isn't still overdue")
        #expect(work.lastTouchedAt != nil, "the check is a touch, as it is from Today")
    }

    // MARK: - R13: one clock

    @Test("Record Practice yesterday reads fresh on the Checklist and in a meeting")
    func practiceYesterdayReadsFresh() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        lesson.id = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Stamp game", lessonID: try #require(lesson.id)
        )
        work.createdAt = day(-60)
        work.assignedAt = day(-60)
        PracticeCheckIns.record(PracticeRecord(date: day(-1), minutes: 20), on: work, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) != .attention)
        let cell = ClassGridEngine.buildCellState(
            lesson: lesson, studentLAs: [], studentWorkModels: [work],
            calendar: AppCalendar.shared, today: day(0)
        )
        #expect(!cell.isStale, "the Checklist dot reads the practice")
        let meeting = MeetingWorkSnapshotHelper.sessionWork([work], workOverdueDays: 14, reviewed: [])
        #expect(meeting.stuck.isEmpty, "practiced yesterday isn't stuck")
        #expect(meeting.open.count == 1)
    }

    @Test("A month's rest doesn't wake as weeks untouched")
    func restEndIsATouch() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Timeline")
        work.createdAt = day(-70)
        work.assignedAt = day(-70)
        work.lastTouchedAt = day(-40)
        // Set aside for a month; the rest ended this morning.
        work.restingUntil = day(0)
        #expect(CoreDataTestHelpers.save(context))

        #expect(!work.isResting)
        #expect(LessonsAndWorkTriage.bucket(for: work, context: context) != .attention)
    }

    // MARK: - R14: practice

    @Test("Work made with no presentation named is Practice once she has been given the lesson")
    func kindFollowsTheResolvedPresentation() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        student.id = UUID()
        lesson.id = UUID()
        let given = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: day(-2), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        // The Checklist's Practicing step and Claude's assign_work pass no presentation.
        let work = try WorkRepository(context: context).createWork(
            studentID: try #require(student.id), lessonID: try #require(lesson.id), saveImmediately: false
        )

        #expect(work.presentationID == given.id?.uuidString)
        #expect(work.kind == .practiceLesson)
    }

    @Test("A practice check-in still to come isn't practice yet")
    func scheduledPracticeIsNotPractice() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp game")
        work.id = UUID()
        let planned = CDWorkCheckIn.make(for: work, on: day(2), purpose: PracticeCheckIns.purpose, in: context)
        let done = PracticeCheckIns.record(PracticeRecord(date: day(-1), minutes: 15), on: work, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(!planned.isPractice)
        #expect(done.isPractice)
        let found = CDWorkCheckIn.practice(onWorkIDs: [try #require(work.id).uuidString], in: context)
        #expect(found.map(\.objectID) == [done.objectID])
    }

    // MARK: - R23: open means the status

    @Test("A shared project finished child by child closes")
    func sharedRowClosesWithItsLastChild() async throws {
        let (tools, context) = try Fixture.makeTools()
        let avigail = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Green")
        let leshem = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem", lastName: "Pardes")
        let row = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster", studentID: try #require(avigail.id))
        row.id = UUID()
        row.sourceContextType = .projectSession
        for student in [avigail, leshem] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(student.id).uuidString
            participant.work = row
        }
        #expect(CoreDataTestHelpers.save(context))
        let update = try Fixture.tool(named: "update_work", in: tools)

        _ = try await update.handler(["work_id": .string(try Fixture.id(of: row)), "completed_by": .string("Leshem")])
        #expect(row.status.isOpen, "Avigail is still working")
        #expect(row.isOpen)

        _ = try await update.handler(["work_id": .string(try Fixture.id(of: row)), "completed_by": .string("Avigail")])
        #expect(row.status.isClosed, "the last child's finish closes the row")
        #expect(row.completedAt != nil)
        #expect(LessonsAndWorkTriage.bucket(for: row, context: context) == .done)
    }

    @Test("Open means the status, whatever the participants' stamps say")
    func openMeansTheStatus() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let studentID = UUID()
        let row = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster", studentID: studentID)
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = studentID.uuidString
        participant.completedAt = day(-1)
        participant.work = row

        // An older build could stamp every child and leave the row Working.
        #expect(row.status == .active)
        #expect(row.isOpen)
    }
}
