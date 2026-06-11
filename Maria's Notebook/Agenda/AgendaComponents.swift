import SwiftUI

struct AgendaSchoolDayRules {
    static func computeInitialStartDate(calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        // Centralize school-day movement rules in PlanningEngine to keep behavior consistent
        // across agenda-style views.
        let today = AppCalendar.startOfDay(Date())
        return PlanningEngine.firstSchoolDay(onOrAfter: today, calendar: calendar, isNonSchoolDay: isNonSchoolDay)
    }

    static func movedStart(
        bySchoolDays delta: Int,
        from start: Date,
        calendar: Calendar,
        isNonSchoolDay: (Date) -> Bool
    ) -> Date {
        let startDay = AppCalendar.startOfDay(start)
        return PlanningEngine.moveBySchoolDays(
            from: startDay,
            days: delta,
            calendar: calendar,
            isNonSchoolDay: isNonSchoolDay
        )
    }
}
