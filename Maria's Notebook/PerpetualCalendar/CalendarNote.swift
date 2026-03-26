import Foundation
import SwiftData

/// Persists a user-editable note for a specific day on the calendar.
/// Year is stored so notes are kept per-year, allowing multi-year history.
@Model final class CalendarNote: Identifiable {
    #Index<CalendarNote>([\.year, \.month, \.day])

    var id: UUID = UUID()
    /// Calendar year (e.g. 2026)
    var year: Int = 2026
    /// Month number (1–12)
    var month: Int = 1
    /// Day number (1–31)
    var day: Int = 1
    /// User-entered event or note text
    var text: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(year: Int, month: Int, day: Int, text: String) {
        self.id = UUID()
        self.year = year
        self.month = month
        self.day = day
        self.text = text
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
