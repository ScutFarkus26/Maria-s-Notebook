import Foundation
import SwiftData

@Model final class NonSchoolDay: Identifiable {
    var id: UUID
    /// Stored as start-of-day for the selected date
    var date: Date
    var reason: String?

    init(id: UUID = UUID(), date: Date, reason: String? = nil) {
        self.id = id
        // Normalize to start of day to ensure uniqueness by day
        self.date = Calendar.current.startOfDay(for: date)
        self.reason = reason
    }
}
