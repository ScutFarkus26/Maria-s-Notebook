import Foundation
import SwiftData

/// A historical record indicating that a student completed a piece of work
/// at a specific point in time. Multiple records for the same (workID, studentID)
/// pair preserve the full completion history.
@Model final class WorkCompletionRecord: Identifiable {
    // MARK: - Identity
    var id: UUID = UUID()

    // MARK: - Foreign Keys (soft references)
    /// The identifier of the work item that was completed.
    // CloudKit compatibility: Store UUID as string
    var workID: String = ""

    /// The identifier of the student who completed the work.
    // CloudKit compatibility: Store UUID as string
    var studentID: String = ""

    // MARK: - Payload
    /// The timestamp when the completion occurred.
    var completedAt: Date = Date()

    // MARK: - Computed Properties for Backward Compatibility
    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }
    
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
    
    // Inverse relationship for Note.workCompletionRecord
    @Relationship(deleteRule: .cascade, inverse: \Note.workCompletionRecord) var notes: [Note]? = []

    // MARK: - Init
    init(
        id: UUID = UUID(),
        workID: UUID,
        studentID: UUID,
        completedAt: Date = .init()
    ) {
        self.id = id
        // CloudKit compatibility: Store UUIDs as strings
        self.workID = workID.uuidString
        self.studentID = studentID.uuidString
        let cal = AppCalendar.shared
        self.completedAt = cal.startOfDay(for: completedAt)
    }
}

