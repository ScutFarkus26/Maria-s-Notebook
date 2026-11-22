import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `PracticeCheckInTiming`: practice comes back the school day before the
/// child's next planned lesson in the sequence, or three school days after the
/// lesson, and moves earlier when a later lesson is planned.
///
/// The week of Monday 2026-11-23 (Thursday 26th and Friday 27th are school
/// days here: no days off are set unless a test adds one).
@Suite("Practice check-in timing")
@MainActor
struct PracticeCheckInTimingTests {

    let ada = UUID()

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    private func lesson(_ name: String, step: Int, in context: NSManagedObjectContext) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: "Addition")
        lesson.id = UUID()
        lesson.orderInSequence = Int64(step)
        return lesson
    }

    /// A plan for `lesson` on `day`, for Ada.
    @discardableResult
    private func plan(
        _ lesson: CDLesson, on day: Date, in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        student.id = ada
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        plan.schedule(onDay: day)
        return plan
    }

    private func days(
        after lesson: CDLesson, givenOn given: Date, lessons: [CDLesson], now: Date,
        in context: NSManagedObjectContext
    ) throws -> Date? {
        PracticeCheckInTiming.checkInDays(
            lessonID: try #require(lesson.id?.uuidString),
            givenOn: given,
            studentIDs: [ada],
            sequences: WorkToShowFirst.Sequences(lessons: lessons),
            in: context,
            now: now
        )[ada]
    }

    // MARK: - A new check-in

    @Test("The check-in is the school day before the next lesson planned in the sequence")
    func dayBeforeNextPlannedLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        plan(second, on: try day("2026-11-27"), in: context)
        let monday = try day("2026-11-23")

        let checkIn = try days(after: first, givenOn: monday, lessons: [first, second], now: monday, in: context)
        #expect(checkIn == (try day("2026-11-26")))
    }

    @Test("With nothing planned it is three school days after the lesson, skipping the weekend")
    func threeSchoolDaysWithNothingPlanned() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let monday = try day("2026-11-23")
        let thursday = try day("2026-11-26")

        #expect(try days(after: first, givenOn: monday, lessons: [first], now: monday, in: context)
            == (try day("2026-11-26")))
        #expect(try days(after: first, givenOn: thursday, lessons: [first], now: thursday, in: context)
            == (try day("2026-12-01")))
    }

    @Test("A day off is skipped, after the lesson and before the next one")
    func skipsNonSchoolDays() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let dayOff = CDNonSchoolDay(context: context)
        dayOff.date = try day("2026-11-25")
        let monday = try day("2026-11-23")

        #expect(try days(after: first, givenOn: monday, lessons: [first, second], now: monday, in: context)
            == (try day("2026-11-27")), "Tuesday, Thursday, Friday")

        plan(second, on: try day("2026-11-26"), in: context)
        #expect(try days(after: first, givenOn: monday, lessons: [first, second], now: monday, in: context)
            == (try day("2026-11-24")), "the school day before Thursday is Tuesday")
    }

    @Test("Never earlier than the next school day after the lesson, nor than today")
    func neverEarlierThanTomorrow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let monday = try day("2026-11-23")
        // The next lesson is tomorrow: the day before it is the lesson's own day.
        plan(second, on: try day("2026-11-24"), in: context)
        #expect(try days(after: first, givenOn: monday, lessons: [first, second], now: monday, in: context)
            == (try day("2026-11-24")))

        // Filed a week late: three school days after it have gone by.
        let context2 = try CoreDataTestHelpers.makeContext()
        let late = lesson("Bead Addition", step: 1, in: context2)
        #expect(try days(after: late, givenOn: try day("2026-11-16"), lessons: [late], now: monday, in: context2)
            == monday)
    }

    @Test("A lesson earlier in the sequence, or another child's plan, isn't the next lesson")
    func onlyHerLaterLessonsCount() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let monday = try day("2026-11-23")
        let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross")
        other.id = UUID()
        PresentationFactory.makeDraft(lesson: second, students: [other], context: context)
            .schedule(onDay: try day("2026-11-24"))
        plan(first, on: try day("2026-11-24"), in: context)

        #expect(try days(after: second, givenOn: monday, lessons: [first, second], now: monday, in: context)
            == (try day("2026-11-26")), "her plan is for an earlier lesson; Ben's isn't hers")
    }

    // MARK: - Filing it

    @Test("Scheduling makes one check-in, and filing again makes no second one")
    func scheduleCheckInsOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let presentationID = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: ada, lessonID: try #require(first.id)
        )
        work.id = UUID()
        work.status = .active
        work.presentationID = presentationID.uuidString
        let thursday = try day("2026-11-26")

        let schedule = {
            PracticeCheckInTiming.scheduleCheckIns(forWorkFrom: presentationID, on: [self.ada: thursday], in: context)
        }
        #expect(schedule() == 1)
        #expect(schedule() == 0)
        let scheduled = WorkLogService.scheduledCheckIns(of: work, in: context)
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.date.map(AppCalendar.startOfDay) == thursday)
    }

    // MARK: - A later lesson planned

    @Test("Planning a later lesson moves an open check-in earlier and leaves a done one")
    func movesOpenCheckInEarlier() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: ada, lessonID: try #require(first.id)
        )
        work.id = UUID()
        work.status = .active
        let late = CDWorkCheckIn.make(for: work, on: try day("2026-11-30"), in: context)
        let done = CDWorkCheckIn.make(for: work, on: try day("2026-12-01"), status: .completed, in: context)
        let soon = CDWorkCheckIn.make(for: work, on: try day("2026-11-24"), in: context)
        let thursday = plan(second, on: try day("2026-11-26"), in: context)

        let moved = PracticeCheckInTiming.followPlannedLessons(
            [thursday], sequences: WorkToShowFirst.Sequences(lessons: [first, second]),
            in: context, now: try day("2026-11-23")
        )
        #expect(moved == 1)
        #expect(late.date.map(AppCalendar.startOfDay) == (try day("2026-11-25")))
        #expect(done.date.map(AppCalendar.startOfDay) == (try day("2026-12-01")), "a done check-in stays")
        #expect(soon.date.map(AppCalendar.startOfDay) == (try day("2026-11-24")), "never later")
    }

    @Test("A moved check-in is never put before today")
    func movedNeverBeforeToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Practice", studentID: ada, lessonID: try #require(first.id)
        )
        work.id = UUID()
        work.status = .active
        let checkIn = CDWorkCheckIn.make(for: work, on: try day("2026-11-30"), in: context)
        let tuesday = try day("2026-11-24")
        let plan = plan(second, on: tuesday, in: context)

        PracticeCheckInTiming.followPlannedLessons(
            [plan], sequences: WorkToShowFirst.Sequences(lessons: [first, second]), in: context, now: tuesday
        )
        #expect(checkIn.date.map(AppCalendar.startOfDay) == tuesday)
    }
}
