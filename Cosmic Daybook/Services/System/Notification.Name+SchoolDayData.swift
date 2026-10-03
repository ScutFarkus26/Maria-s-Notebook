import Foundation

// Its own file (not `SchoolCalendarService`'s) so the Daybook Assistant, which
// compiles it by path, gets the name without the school-calendar service.

extension Notification.Name {
    /// Posted when school-day data (explicit non-school days or weekend
    /// overrides) changes — via a local edit or a CloudKit sync. Observers
    /// invalidate any cached school-day calculations. See
    /// `AppDependencies.invalidateSchoolDayCaches()`.
    static let schoolDayDataDidChange = Notification.Name("schoolDayDataDidChange")
}
