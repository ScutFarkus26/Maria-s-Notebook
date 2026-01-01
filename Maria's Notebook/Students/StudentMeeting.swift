import Foundation
import SwiftData

@Model
final class StudentMeeting: Identifiable {
    @Attribute(.unique) var id: UUID
    var studentID: UUID
    var date: Date
    var completed: Bool
    var reflection: String
    var focus: String
    var requests: String
    var guideNotes: String

    init(
        id: UUID = UUID(),
        studentID: UUID,
        date: Date = Date(),
        completed: Bool = false,
        reflection: String = "",
        focus: String = "",
        requests: String = "",
        guideNotes: String = ""
    ) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.completed = completed
        self.reflection = reflection
        self.focus = focus
        self.requests = requests
        self.guideNotes = guideNotes
    }
}
