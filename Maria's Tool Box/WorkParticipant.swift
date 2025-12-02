import Foundation
import SwiftData

@Model final class WorkParticipant: Identifiable {
    var id: UUID
    var studentID: UUID
    var completedAt: Date?

    init(id: UUID = UUID(), studentID: UUID, completedAt: Date? = nil) {
        self.id = id
        self.studentID = studentID
        self.completedAt = completedAt
    }
}
