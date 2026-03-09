import Foundation
import SwiftData

@Model
final class ScheduledMeeting: Identifiable {
    #Index<ScheduledMeeting>([\.studentID, \.date])

    var id: UUID = UUID()
    /// CloudKit compatibility: Store UUID as string.
    var studentID: String = ""
    /// Normalized to start of day.
    var date: Date = Date()
    var createdAt: Date = Date()

    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        studentID: UUID,
        date: Date
    ) {
        self.id = id
        self.studentID = studentID.uuidString
        self.date = AppCalendar.startOfDay(date)
        self.createdAt = Date()
    }
}
