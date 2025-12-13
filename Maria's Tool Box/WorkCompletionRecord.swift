import Foundation
import SwiftData

/// A historical record indicating that a student completed a piece of work
/// at a specific point in time. Multiple records for the same (workID, studentID)
/// pair preserve the full completion history.
@Model final class WorkCompletionRecord: Identifiable {
    // MARK: - Identity
    var id: UUID

    // MARK: - Foreign Keys (soft references)
    /// The identifier of the work item that was completed.
    var workID: UUID

    /// The identifier of the student who completed the work.
    var studentID: UUID

    // MARK: - Payload
    /// The timestamp when the completion occurred.
    var completedAt: Date

    /// Optional free-form note or context captured at completion time.
    var note: String

    // MARK: - Init
    init(
        id: UUID = UUID(),
        workID: UUID,
        studentID: UUID,
        completedAt: Date = .init(),
        note: String = ""
    ) {
        self.id = id
        self.workID = workID
        self.studentID = studentID
        let cal = AppCalendar.shared
        self.completedAt = cal.startOfDay(for: completedAt)
        self.note = note
    }
}

