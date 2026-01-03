import Foundation
import SwiftData

@Model final class SchoolDayOverride: Identifiable {
    var id: UUID = UUID()
    /// Stored as start-of-day for the selected date
    var date: Date = Date()
    var note: String?
    
    // Inverse relationship for Note.schoolDayOverride
    @Relationship(deleteRule: .cascade, inverse: \Note.schoolDayOverride) var notes: [Note]? = []

    init(id: UUID = UUID(), date: Date, note: String? = nil) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.note = note
    }
}
