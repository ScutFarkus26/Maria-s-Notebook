import Foundation
import SwiftData

@Model final class SchoolDayOverride: Identifiable {
    #Index<SchoolDayOverride>([\.date])
    
    var id: UUID = UUID()
    /// Stored as start-of-day for the selected date - indexed for calendar queries
    var date: Date = Date()

    // Inverse relationship for Note.schoolDayOverride
    @Relationship(deleteRule: .cascade, inverse: \Note.schoolDayOverride) var notes: [Note]? = []

    init(id: UUID = UUID(), date: Date) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
    }
}
