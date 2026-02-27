import Foundation
import SwiftData

@Model
final class StudentMeeting: Identifiable {
    #Index<StudentMeeting>([\.studentID], [\.completed])

    var id: UUID = UUID()
    // CloudKit compatibility: Store UUID as string
    var studentID: String = ""
    var date: Date = Date()
    var completed: Bool = false
    var reflection: String = ""
    var focus: String = ""
    var requests: String = ""
    var guideNotes: String = ""
    
    // Computed property for backward compatibility with UUID
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
    
    // Inverse relationship for Note.studentMeeting
    @Relationship(deleteRule: .cascade, inverse: \Note.studentMeeting) var notes: [Note]? = []

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
        // CloudKit compatibility: Store UUID as string
        self.studentID = studentID.uuidString
        self.date = date
        self.completed = completed
        self.reflection = reflection
        self.focus = focus
        self.requests = requests
        self.guideNotes = guideNotes
    }
}
