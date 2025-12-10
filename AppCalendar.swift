import Foundation

/// Centralized calendar for day-boundary normalization across the app.
/// Use this calendar whenever you denormalize dates to `startOfDay(for:)` so
/// Planning, Today, and model denormalization stay in sync.
enum AppCalendar {
    /// Shared calendar used for all date normalization.
    /// Defaults to Gregorian with the current time zone.
    static var shared: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    /// Update the shared calendar's time zone to match the provided calendar.
    /// Call this early in app lifecycle if you use a custom environment calendar.
    static func adopt(timeZoneFrom calendar: Calendar) {
        var cal = shared
        cal.timeZone = calendar.timeZone
        shared = cal
    }
}
