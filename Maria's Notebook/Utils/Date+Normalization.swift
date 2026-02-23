import Foundation

/// Date extensions for consistent date normalization and comparison
/// Centralizes date handling logic using AppCalendar
extension Date {
    /// Returns the start of day for this date using AppCalendar
    /// This is the normalized representation used throughout the app
    var startOfDay: Date {
        AppCalendar.startOfDay(self)
    }
    
    /// Checks if this date is on the same day as another date
    /// - Parameter other: The other date to compare
    /// - Returns: `true` if both dates are on the same day, `false` otherwise
    func isSameDay(as other: Date) -> Bool {
        self.startOfDay == other.startOfDay
    }
    
    /// Checks if this date is before another date (comparing start of day)
    /// - Parameter other: The other date to compare
    /// - Returns: `true` if this date's start of day is before the other's
    func isBeforeDay(_ other: Date) -> Bool {
        self.startOfDay < other.startOfDay
    }
    
    /// Checks if this date is after another date (comparing start of day)
    /// - Parameter other: The other date to compare
    /// - Returns: `true` if this date's start of day is after the other's
    func isAfterDay(_ other: Date) -> Bool {
        self.startOfDay > other.startOfDay
    }
    
    /// Calculates the age in years from this date to now
    /// - Returns: The number of complete years between this date and now, or nil if calculation fails
    var age: Int? {
        Calendar.current.dateComponents([.year], from: self, to: Date()).year
    }
}

