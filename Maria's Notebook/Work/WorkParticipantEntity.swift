import Foundation
import SwiftData

@Model final class WorkParticipantEntity: Identifiable {
    // Identity (optional but useful for list operations)
    var id: UUID = UUID()

    // The identifier of the student participating in the work
    // CloudKit compatibility: Store UUID as string
    var studentID: String = ""

    // The timestamp when the student completed the work (nil if not completed)
    var completedAt: Date? = nil

    // Relationship back to the parent work item (inverse specified on WorkModel.participants)
    @Relationship var work: WorkModel? = nil
    
    // Computed property for backward compatibility with UUID
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        studentID: UUID,
        completedAt: Date? = nil,
        work: WorkModel? = nil
    ) {
        self.id = id
        // CloudKit compatibility: Store UUID as string
        self.studentID = studentID.uuidString
        // Use AppCalendar for consistent date normalization across the app
        self.completedAt = completedAt.map { AppCalendar.startOfDay($0) }
        self.work = work
    }
}
