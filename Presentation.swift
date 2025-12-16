import Foundation
import SwiftData

/// Immutable record of a group presentation ("teacher time").
/// Once created, treat as read-only history.
@Model
final class Presentation: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var presentedAt: Date

    // Legacy references (store UUIDs as strings for CloudKit friendliness)
    var lessonID: String
    var studentIDs: [String]
    var legacyStudentLessonID: String?

    // Snapshots to keep history stable even if source lesson changes later
    var lessonTitleSnapshot: String?
    var lessonSubtitleSnapshot: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        presentedAt: Date,
        lessonID: String,
        studentIDs: [String],
        legacyStudentLessonID: String? = nil,
        lessonTitleSnapshot: String? = nil,
        lessonSubtitleSnapshot: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.presentedAt = presentedAt
        self.lessonID = lessonID
        self.studentIDs = studentIDs
        self.legacyStudentLessonID = legacyStudentLessonID
        self.lessonTitleSnapshot = lessonTitleSnapshot
        self.lessonSubtitleSnapshot = lessonSubtitleSnapshot
    }

    /// Convenience: map string IDs to UUIDs, dropping invalid values.
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }
}

#if DEBUG
extension Presentation {
    var debugDescription: String {
        let count = studentIDs.count
        return "Presentation(id=\(id), lessonID=\(lessonID.prefix(8))…, students=\(count), presentedAt=\(presentedAt))"
    }
}
#endif
