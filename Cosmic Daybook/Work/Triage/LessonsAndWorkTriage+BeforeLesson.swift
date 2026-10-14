// LessonsAndWorkTriage+BeforeLesson.swift
// Which presentations the Work half's "Before a Lesson" pill looks ahead to.
//
// The pill lists open work that children in an upcoming lesson still have
// from earlier in that lesson's sequence (`WorkToShowFirst`). "Upcoming" is
// the next three school days, today included when it is one. It is a lens
// over open work, not a triage bucket: the same work is also in Needs
// Checking, To Schedule or Scheduled, so it isn't a `TriageBucket`, whose
// lists never overlap.
//
// Pure, like the rest of the rule: the school calendar arrives as a closure,
// so the window is testable without a store.

import Foundation

extension LessonsAndWorkTriage {

    /// School days "Before a Lesson" looks ahead, today included.
    static let beforeLessonSchoolDays = 3

    /// The start of each of the next `count` school days from `now`: today
    /// when it is a school day, then the ones after it, skipping weekends,
    /// holidays and anything else `isSchoolDay` says no to.
    static func beforeLessonDays(
        from now: Date,
        count: Int = beforeLessonSchoolDays,
        isSchoolDay: (Date) -> Bool
    ) -> [Date] {
        var days: [Date] = []
        var cursor = AppCalendar.startOfDay(now)
        var looked = 0
        // A year of non-school days in a row is more than any calendar holds.
        while days.count < count && looked < 366 {
            if isSchoolDay(cursor) { days.append(cursor) }
            cursor = AppCalendar.addingDays(1, to: cursor)
            looked += 1
        }
        return days
    }

    /// Whether a presentation is one "Before a Lesson" looks ahead to: not
    /// given yet, and planned for one of `days` (from `beforeLessonDays`).
    static func isBeforeLesson(_ presentation: PresentationTriageInput, days: [Date]) -> Bool {
        guard presentation.state != .presented, let scheduledFor = presentation.scheduledFor else { return false }
        return days.contains(AppCalendar.startOfDay(scheduledFor))
    }
}
