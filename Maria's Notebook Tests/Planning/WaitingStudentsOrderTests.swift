import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The waiting list decides who the guide sees, so the ordering and the
/// filtering are worth pinning: a child sorted to the bottom, or filtered out,
/// is a child who silently stops being taught.
@Suite("Waiting students order")
@MainActor
struct WaitingStudentsOrderTests {

    private func makeStudent(
        _ context: NSManagedObjectContext,
        first: String,
        last: String
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        return student
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
        )
    }

    // MARK: - "Never taught"

    @Test("Every spelling of never-taught means the same thing")
    func neverTaughtSentinelsAgree() {
        // PresentationsViewModel says Int.max, StudentsViewModel says -1, other
        // callers say nil, and a child absent from the map was never counted.
        #expect(WaitingStudentsOrder.daysWaiting(from: Int.max) == nil)
        #expect(WaitingStudentsOrder.daysWaiting(from: -1) == nil)
        #expect(WaitingStudentsOrder.daysWaiting(from: nil) == nil)
        // A real count survives, including zero.
        #expect(WaitingStudentsOrder.daysWaiting(from: 0) == 0)
        #expect(WaitingStudentsOrder.daysWaiting(from: 14) == 14)
    }

    @Test("A child who has never been taught sorts above everyone")
    func neverTaughtSortsFirst() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let never = makeStudent(context, first: "Ada", last: "Byron")
        let waiting = makeStudent(context, first: "Bram", last: "Cole")

        let ordered = WaitingStudentsOrder.ordered(
            students: [waiting, never],
            daysSince: [never.id!: Int.max, waiting.id!: 40],
            studentIDsWithUpcomingLessons: [],
            scope: .everyone
        )

        #expect(ordered.map(\.student.id) == [never.id, waiting.id])
        #expect(ordered.first?.isNeverTaught == true)
    }

    // MARK: - Order

    @Test("Longest wait comes first")
    func longestWaitFirst() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let recent = makeStudent(context, first: "Ada", last: "One")
        let middle = makeStudent(context, first: "Bram", last: "Two")
        let stale = makeStudent(context, first: "Cleo", last: "Three")

        let ordered = WaitingStudentsOrder.ordered(
            students: [recent, middle, stale],
            daysSince: [recent.id!: 1, middle.id!: 9, stale.id!: 30],
            studentIDsWithUpcomingLessons: [],
            scope: .everyone
        )

        #expect(ordered.map(\.student.id) == [stale.id, middle.id, recent.id])
    }

    @Test("Children who have waited the same length keep a stable order")
    func equalWaitsBreakByName() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        // The list this replaces had no tie-break, so equal-day children
        // reshuffled every time it rebuilt.
        let zara = makeStudent(context, first: "Zara", last: "Ames")
        let adam = makeStudent(context, first: "Adam", last: "Bell")

        let ordered = WaitingStudentsOrder.ordered(
            students: [zara, adam],
            daysSince: [zara.id!: 7, adam.id!: 7],
            studentIDsWithUpcomingLessons: [],
            scope: .everyone
        )

        #expect(ordered.map(\.student.id) == [adam.id, zara.id])
    }

    // MARK: - The filter

    @Test("Unscheduled hides children who already have something coming up")
    func unscheduledScopeFiltersBookedChildren() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let booked = makeStudent(context, first: "Ada", last: "One")
        let free = makeStudent(context, first: "Bram", last: "Two")

        let everyone = WaitingStudentsOrder.ordered(
            students: [booked, free],
            daysSince: [booked.id!: 20, free.id!: 5],
            studentIDsWithUpcomingLessons: [booked.id!],
            scope: .everyone
        )
        #expect(everyone.count == 2)

        let unscheduled = WaitingStudentsOrder.ordered(
            students: [booked, free],
            daysSince: [booked.id!: 20, free.id!: 5],
            studentIDsWithUpcomingLessons: [booked.id!],
            scope: .unscheduled
        )
        #expect(unscheduled.map(\.student.id) == [free.id])
    }

    @Test("Searching narrows the list by name")
    func searchNarrowsByName() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let bram = makeStudent(context, first: "Bram", last: "Cole")

        let ordered = WaitingStudentsOrder.ordered(
            students: [ada, bram],
            daysSince: [ada.id!: 10, bram.id!: 20],
            studentIDsWithUpcomingLessons: [],
            scope: .everyone,
            search: "ada"
        )

        #expect(ordered.map(\.student.id) == [ada.id])
    }

    // MARK: - What counts as "already scheduled"

    @Test("A lesson still to come counts; one whose day has passed does not")
    func upcomingOnlyCountsFutureLessons() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let today = day(2026, 6, 10)

        let student = makeStudent(context, first: "Ada", last: "Byron")

        // A lesson booked for March that was never given. The list this
        // replaces counted it forever, so this child could never appear under
        // Unscheduled again — the reason for not reusing that predicate.
        let stale = CDLessonAssignment(context: context)
        stale.id = UUID()
        stale.studentIDs = [student.id!.uuidString]
        stale.schedule(for: day(2026, 3, 2))

        #expect(
            WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: [stale], asOf: today).isEmpty
        )

        let upcoming = CDLessonAssignment(context: context)
        upcoming.id = UUID()
        upcoming.studentIDs = [student.id!.uuidString]
        upcoming.schedule(for: day(2026, 6, 12))

        #expect(
            WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: [upcoming], asOf: today)
                == Set([student.id!])
        )
    }

    @Test("A lesson booked for today still counts as coming up")
    func todayCountsAsUpcoming() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let today = day(2026, 6, 10)
        let student = makeStudent(context, first: "Ada", last: "Byron")

        let assignment = CDLessonAssignment(context: context)
        assignment.id = UUID()
        assignment.studentIDs = [student.id!.uuidString]
        assignment.schedule(onDay: today)

        #expect(
            WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: [assignment], asOf: today)
                == Set([student.id!])
        )
    }

    @Test("A lesson already given never counts, whatever day it sits on")
    func givenLessonsDoNotCount() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let today = day(2026, 6, 10)
        let student = makeStudent(context, first: "Ada", last: "Byron")

        let given = CDLessonAssignment(context: context)
        given.id = UUID()
        given.studentIDs = [student.id!.uuidString]
        given.schedule(for: day(2026, 6, 12))
        given.markPresented(at: day(2026, 6, 12), snapshotLesson: false)

        #expect(
            WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: [given], asOf: today).isEmpty
        )
    }
}
