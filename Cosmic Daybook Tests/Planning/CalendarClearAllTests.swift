import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// "Clear All to Inbox" on the Lessons & Work calendar (2026-10-13): every
/// planned presentation goes back to the Inbox and every open work check
/// comes off the calendar with it, linked copies included; a check carrying
/// a note is marked skipped rather than deleted, so the note stays; and Undo
/// puts all of it back.
@Suite("Calendar Clear All")
@MainActor
struct CalendarClearAllTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    private func time(_ hour: Int, _ minute: Int = 0, on base: Date) -> Date {
        AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    /// Linked copies the way assign_work makes them.
    private func seedLinkedCopies(in context: NSManagedObjectContext, count: Int) -> [CDWorkModel] {
        let lessonID = UUID()
        let works = (0..<count).map { _ in
            CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Checkerboard practice", studentID: UUID(), lessonID: lessonID
            )
        }
        for work in works {
            work.kind = .followUpAssignment
            for named in works {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = named.studentID
                participant.work = work
            }
        }
        return works
    }

    /// Monday's plan: a presentation; a work with an overdue check and one
    /// for Tuesday; a work whose Monday check carries a note; and two linked
    /// copies with Tuesday checks.
    private struct Plan {
        let context: NSManagedObjectContext
        let monday: Date
        let lastThursday: Date
        let tuesday: Date
        let assignment: CDLessonAssignment
        let work: CDWorkModel
        let overdue: CDWorkCheckIn
        let upcoming: CDWorkCheckIn
        let noted: CDWorkModel
        let notedCheck: CDWorkCheckIn
        let copies: [CDWorkModel]
        let copyChecks: [CDWorkCheckIn]
    }

    private func seedPlan() throws -> Plan {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lastThursday = day(2026, 6, 4)
        let monday = day(2026, 6, 8)
        let tuesday = day(2026, 6, 9)
        let assignment = CDLessonAssignment(context: context)
        assignment.schedule(for: time(9, 30, on: monday), using: AppCalendar.shared)

        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.dueAt = lastThursday
        let overdue = CDWorkCheckIn.make(for: work, on: time(13, on: lastThursday), in: context)
        let upcoming = CDWorkCheckIn.make(for: work, on: time(13, on: tuesday), in: context)

        let noted = CoreDataTestHelpers.seedWorkModel(in: context)
        noted.dueAt = monday
        let notedCheck = CDWorkCheckIn.make(for: noted, on: time(14, on: monday), in: context)
        notedCheck.setLegacyNoteText("Bring the bead frame", in: context)

        let copies = seedLinkedCopies(in: context, count: 2)
        let copyChecks = copies.map { CDWorkCheckIn.make(for: $0, on: time(10, on: tuesday), in: context) }
        copies.forEach { $0.dueAt = tuesday }
        #expect(CoreDataTestHelpers.save(context))
        return Plan(
            context: context, monday: monday, lastThursday: lastThursday, tuesday: tuesday,
            assignment: assignment, work: work, overdue: overdue, upcoming: upcoming,
            noted: noted, notedCheck: notedCheck, copies: copies, copyChecks: copyChecks
        )
    }

    @Test("Clear All unschedules presentations and work checks, resets due days, and skips a noted check")
    func clearAllTakesEverythingOff() throws {
        let plan = try seedPlan()

        let pending = CalendarClearAllService.pending(in: plan.context)
        let cleared = CalendarClearAllService.clearAll(in: plan.context)

        #expect(pending == cleared)
        #expect(cleared.presentations == 1 && cleared.checkIns == 5 && cleared.keptForNotes == 1)
        #expect(plan.assignment.scheduledFor == nil)
        let removed = ([plan.overdue, plan.upcoming] + plan.copyChecks).map(\.isDeleted)
        #expect(removed == [true, true, true, true])
        #expect(plan.work.dueAt == nil)
        #expect(plan.copies.allSatisfy { $0.dueAt == nil })
        let triage = WorkTriageInput(
            status: plan.work.status, dueAt: plan.work.dueAt,
            scheduledCheckInDates: WorkLogService.scheduledCheckIns(of: plan.work, in: plan.context)
                .compactMap(\.date)
        )
        #expect(LessonsAndWorkTriage.bucket(for: triage, asOf: plan.monday) == .toSchedule)
        // The noted check is skipped where it was, note and all, so it leaves
        // the strip and its work goes back to To Schedule too.
        #expect(!plan.notedCheck.isDeleted)
        #expect(plan.notedCheck.status == .skipped)
        #expect(plan.notedCheck.date == time(14, on: plan.monday))
        #expect(plan.notedCheck.legacyNoteText == "Bring the bead frame")
        #expect(plan.noted.dueAt == nil)
        #expect(CalendarForwardShiftService.movableCheckIns(in: plan.context).isEmpty)
        #expect(CoreDataTestHelpers.save(plan.context))
    }

    @Test("Undo after Clear All puts every presentation, check and due day back")
    func undoPutsItAllBack() throws {
        let plan = try seedPlan()
        let removedIDs = ([plan.overdue, plan.upcoming] + plan.copyChecks).compactMap(\.id)
        let overdueID = try #require(plan.overdue.id)
        let cleared = CalendarClearAllService.clearAll(in: plan.context)
        #expect(CoreDataTestHelpers.save(plan.context))

        let restored = CalendarClearAllService.undo(cleared.receipt, in: plan.context, calendar: AppCalendar.shared)
        #expect(CoreDataTestHelpers.save(plan.context))

        #expect(restored == 6)
        #expect(plan.assignment.scheduledFor == time(9, 30, on: plan.monday))
        #expect(plan.work.dueAt == plan.lastThursday)
        #expect(plan.copies.allSatisfy { $0.dueAt == plan.tuesday })
        for id in removedIDs {
            let checkIn = try #require(plan.context.object(CDWorkCheckIn.self, id: id))
            #expect(checkIn.status == .scheduled)
            #expect(checkIn.resolvedWork(in: plan.context) != nil)
        }
        // The noted check is scheduled again on its day, with its note.
        #expect(plan.notedCheck.status == .scheduled)
        #expect(plan.notedCheck.legacyNoteText == "Bring the bead frame")
        #expect(plan.noted.dueAt == plan.monday)
        let back = try #require(plan.context.object(CDWorkCheckIn.self, id: overdueID))
        #expect(back.date == time(13, on: plan.lastThursday))
        #expect(WorkLogService.scheduledCheckIns(of: plan.work, in: plan.context).count == 2)
        // A second Undo makes nothing twice.
        #expect(CalendarClearAllService.undo(cleared.receipt, in: plan.context, calendar: AppCalendar.shared) == 0)
    }

    @Test("A note logged on the work that day belongs to the work, so its check is deleted and the note stays")
    func workNoteDoesNotKeepACheck() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.dueAt = monday
        let checkIn = CDWorkCheckIn.make(for: work, on: time(10, on: monday), in: context)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Counted to a thousand")
        note.work = work
        note.workCheckIn = checkIn
        #expect(CoreDataTestHelpers.save(context))

        #expect(!WorkCheckInService.hasNote(checkIn))
        let pending = CalendarClearAllService.pending(in: context)
        let cleared = CalendarClearAllService.clearAll(in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(pending == cleared)
        #expect(cleared.checkIns == 1 && cleared.keptForNotes == 0)
        #expect(checkIn.isDeleted || checkIn.managedObjectContext == nil)
        #expect(!note.isDeleted && note.managedObjectContext != nil)
        #expect(note.work == work)
        #expect(work.dueAt == nil)
    }

    @Test("Clear All leaves finished work's checks and given presentations alone")
    func clearAllLeavesHistory() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = day(2026, 6, 8)
        let given = CDLessonAssignment(context: context)
        given.schedule(for: time(9, on: monday), using: AppCalendar.shared)
        given.markPresented(at: time(9, on: monday), snapshotLesson: false)
        let closed = CoreDataTestHelpers.seedWorkModel(in: context)
        closed.status = .mastered
        let closedCheck = CDWorkCheckIn.make(for: closed, on: time(10, on: monday), in: context)
        let open = CoreDataTestHelpers.seedWorkModel(in: context)
        let done = CDWorkCheckIn.make(for: open, on: time(10, on: monday), status: .completed, in: context)

        let cleared = CalendarClearAllService.clearAll(in: context)

        #expect(cleared.isEmpty)
        #expect(!closedCheck.isDeleted)
        #expect(!done.isDeleted)
        #expect(given.presentedAt == time(9, on: monday))
    }
}
