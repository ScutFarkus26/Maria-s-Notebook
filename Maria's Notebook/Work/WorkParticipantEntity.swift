import Foundation
import SwiftData

@Model final class WorkParticipantEntity: Identifiable {
    // Identity (optional but useful for list operations)
    @Attribute(.unique) var id: UUID = UUID()

    // The identifier of the student participating in the work
    var studentID: UUID = UUID()

    // The timestamp when the student completed the work (nil if not completed)
    var completedAt: Date? = nil

    // Relationship back to the parent work item
    var work: WorkModel? = nil

    init(
        id: UUID = UUID(),
        studentID: UUID,
        completedAt: Date? = nil,
        work: WorkModel? = nil
    ) {
        self.id = id
        self.studentID = studentID
        let cal = AppCalendar.shared
        self.completedAt = completedAt.map { cal.startOfDay(for: $0) }
        self.work = work
    }
}

