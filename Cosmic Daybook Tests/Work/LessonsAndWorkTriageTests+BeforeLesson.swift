import Foundation
import Testing
@testable import CosmicDaybook

/// The Work half's "Before a Lesson" pill looks ahead three school days,
/// today included, and is a lens over open work rather than a fourth list.
extension LessonsAndWorkTriageTests {

    /// A June 2026 day, at its start.
    private func june(_ dayOfMonth: Int) throws -> Date {
        let date = try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: dayOfMonth)))
        return AppCalendar.startOfDay(date)
    }

    /// Monday to Friday, less `holidays`.
    private func schoolDays(except holidays: [Date] = []) -> (Date) -> Bool {
        { day in
            let weekday = AppCalendar.shared.component(.weekday, from: day)
            return weekday != 1 && weekday != 7 && !holidays.contains(AppCalendar.startOfDay(day))
        }
    }

    @Test("Before a Lesson looks at today and the next two school days")
    func beforeLessonWindowStartsToday() throws {
        // Wednesday 10 June 2026, in the afternoon.
        let now = try june(10).addingTimeInterval(15 * 3_600)
        let days = LessonsAndWorkTriage.beforeLessonDays(from: now, isSchoolDay: schoolDays())
        #expect(days == [try june(10), try june(11), try june(12)])
    }

    @Test("The window skips the weekend and a day off")
    func beforeLessonWindowSkipsNonSchoolDays() throws {
        // Thursday, with Friday off: Thursday, then Monday and Tuesday.
        let days = LessonsAndWorkTriage.beforeLessonDays(
            from: try june(11), isSchoolDay: schoolDays(except: [try june(12)])
        )
        #expect(days == [try june(11), try june(15), try june(16)])

        // From a Saturday, today isn't a school day: Monday to Wednesday.
        let fromWeekend = LessonsAndWorkTriage.beforeLessonDays(from: try june(13), isSchoolDay: schoolDays())
        #expect(fromWeekend == [try june(15), try june(16), try june(17)])

        // A calendar with no school days at all gives an empty window, not a hang.
        #expect(LessonsAndWorkTriage.beforeLessonDays(from: try june(13)) { _ in false }.isEmpty)
    }

    @Test("Only a lesson not yet given, planned in the window, counts")
    func beforeLessonPresentations() throws {
        let days = [try june(10), try june(11), try june(12)]
        let thursdayAfternoon = try june(11).addingTimeInterval(14 * 3_600)
        let inWindow = PresentationTriageInput(state: .scheduled, scheduledFor: thursdayAfternoon)
        #expect(LessonsAndWorkTriage.isBeforeLesson(inWindow, days: days))

        let nextWeek = PresentationTriageInput(state: .scheduled, scheduledFor: try june(15))
        let yesterday = PresentationTriageInput(state: .scheduled, scheduledFor: try june(9))
        let given = PresentationTriageInput(state: .presented, scheduledFor: try june(10))
        let unplanned = PresentationTriageInput(state: .draft)
        for outside in [nextWeek, yesterday, given, unplanned] {
            #expect(!LessonsAndWorkTriage.isBeforeLesson(outside, days: days))
        }
    }

    @Test("Before a Lesson is a pill over open work, not a fourth list")
    func beforeLessonIsALens() {
        #expect(WorkFilterChip.beforeLesson.bucket == nil)
        #expect(WorkFilterChip.beforeLesson.title == "Before a Lesson")
        #expect(TriageBucket.allCases == [.attention, .scheduled, .toSchedule, .done])
        let split = TriageSplit([1, 2, 3]) { _ in .attention }
        #expect(WorkFilterChip.beforeLesson.slice(of: split).isEmpty)
        #expect(WorkFilterChip.showing(.attention) == .needsChecking)
    }
}
