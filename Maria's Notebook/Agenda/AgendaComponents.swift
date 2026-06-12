import SwiftUI

struct AgendaSchoolDayRules {
    static func computeInitialStartDate(calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        // Centralize school-day movement rules in PlanningEngine to keep behavior consistent
        // across agenda-style views.
        let today = AppCalendar.startOfDay(Date())
        return PlanningEngine.firstSchoolDay(onOrAfter: today, calendar: calendar, isNonSchoolDay: isNonSchoolDay)
    }

}
