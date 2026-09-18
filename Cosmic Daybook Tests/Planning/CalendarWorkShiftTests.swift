import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The two ways work moves on the Lessons & Work calendar: dragged by the pill
/// it sits in, and pushed by "Move All Forward 1 Day".
///
/// Both used to lose the work. A grouped pill dragged only the check-in it was
/// keyed on, so a lesson given to four children split into one moved child and
/// three left behind; and the bulk move touched presentations alone, so a
/// pushed week left every work check a day behind the lesson that produced it.
@Suite("Calendar work shifts")
@MainActor
struct CalendarWorkShiftTests {

    // MARK: - Fixtures

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    private func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, on base: Date) -> Date {
        AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: second, of: base)!
    }

    @discardableResult
    private func seedCheckIn(
        in context: NSManagedObjectContext,
        workID: UUID,
        date: Date,
        status: WorkCheckInStatus = .scheduled,
        purpose: String = "progressCheck"
    ) -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = workID.uuidString
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose
        return checkIn
    }

    private func group(_ checkIns: [CDWorkCheckIn]) -> CalendarCheckInGroup {
        CalendarCheckInGroup(
            id: checkIns[0].id ?? UUID(),
            checkIns: checkIns,
            lessonTitle: "The Commutative Law of Multiplication",
            studentNames: ["Ora P", "Avital B", "Avigail G", "Leshem P"],
            purpose: "progressCheck",
            sortDate: checkIns[0].date ?? Date()
        )
    }

    /// A weekend-skipping next-school-day, injected so the shift under test does
    /// not depend on the school-day cache.
    private func nextWeekday(after date: Date) -> Date {
        var cursor = AppCalendar.shared.date(byAdding: .day, value: 1, to: date)!
        while AppCalendar.shared.isDateInWeekend(cursor) {
            cursor = AppCalendar.shared.date(byAdding: .day, value: 1, to: cursor)!
        }
        return cursor
    }

    // MARK: - Dragging a pill

    @Test("A grouped pill drags every child's check-in, the primary first")
    func groupedPillCarriesEveryCheckIn() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let workID = UUID()
        let monday = day(2026, 6, 8)
        let checkIns = (0..<4).map { _ in seedCheckIn(in: context, workID: workID, date: monday) }

        let payloads = UnifiedCalendarDragPayload.parseAll(group(checkIns).dragPayload)

        #expect(payloads.count == 4)
        #expect(payloads.map(\.id) == checkIns.map { $0.id! })
        #expect(payloads.allSatisfy { $0.kind == "workCheckIn" })
    }

    @Test("A drop site that only reads the first line still gets the pill's primary")
    func legacyParseStillGetsThePrimary() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let workID = UUID()
        let checkIns = (0..<3).map { _ in
            seedCheckIn(in: context, workID: workID, date: day(2026, 6, 8))
        }
        let sequence = group(checkIns)

        #expect(UnifiedCalendarDragPayload.parse(sequence.dragPayload) == .workCheckIn(sequence.primary.id!))
    }

    @Test("A single check-in still drags as one record")
    func ungroupedPillCarriesOne() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let checkIn = seedCheckIn(in: stack.viewContext, workID: UUID(), date: day(2026, 6, 8))

        #expect(UnifiedCalendarDragPayload.parseAll(group([checkIn]).dragPayload) == [.workCheckIn(checkIn.id!)])
    }

    // MARK: - Moving the whole plan forward

    @Test("Moving forward carries the work checks along with the presentations")
    func forwardShiftMovesBothKinds() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let monday = day(2026, 6, 8)
        let tuesday = day(2026, 6, 9)

        let assignment = CDLessonAssignment(context: context)
        assignment.schedule(for: time(9, 30, on: monday), using: AppCalendar.shared)

        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.dueAt = monday
        let checkIn = seedCheckIn(in: context, workID: work.id!, date: time(13, 15, on: monday))

        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context,
            calendar: AppCalendar.shared,
            nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved == CalendarForwardShiftService.Result(presentations: 1, checkIns: 1))
        #expect(assignment.scheduledFor == time(9, 30, on: tuesday))
        #expect(checkIn.date == time(13, 15, on: tuesday))
        // The work's due date travels with its check, or the two disagree about
        // which day the child is being seen on.
        #expect(work.dueAt == time(13, 15, on: tuesday))
    }

    @Test("A Friday's work lands on Monday, on the same day as the Friday's lessons")
    func forwardShiftSkipsTheWeekendForBothKinds() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let friday = day(2026, 6, 12)
        let monday = day(2026, 6, 15)

        let assignment = CDLessonAssignment(context: context)
        assignment.schedule(for: time(10, 0, on: friday), using: AppCalendar.shared)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let checkIn = seedCheckIn(in: context, workID: work.id!, date: time(10, 0, on: friday))

        CalendarForwardShiftService.moveForwardOneDay(
            in: context,
            calendar: AppCalendar.shared,
            nextSchoolDay: nextWeekday(after:)
        )

        #expect(assignment.scheduledFor == time(10, 0, on: monday))
        #expect(checkIn.date == time(10, 0, on: monday))
    }

    @Test("What already happened stays where it happened")
    func forwardShiftLeavesFinishedRecordsAlone() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let monday = day(2026, 6, 8)

        let given = CDLessonAssignment(context: context)
        given.schedule(for: time(9, 0, on: monday), using: AppCalendar.shared)
        given.markPresented(at: time(9, 0, on: monday), snapshotLesson: false)

        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let done = seedCheckIn(in: context, workID: work.id!, date: monday, status: .completed)

        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: context,
            calendar: AppCalendar.shared,
            nextSchoolDay: nextWeekday(after:)
        )

        #expect(moved.isEmpty)
        #expect(done.date == monday)
        #expect(given.presentedAt == time(9, 0, on: monday))
    }
}
