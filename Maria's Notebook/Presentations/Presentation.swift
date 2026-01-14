import Foundation
import SwiftData

/// Immutable record of a group presentation ("teacher time").
/// Once created, treat as read-only history.
@Model
final class Presentation: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var presentedAt: Date = Date()

    // Legacy references (store UUIDs as strings for CloudKit friendliness)
    var lessonID: String = ""
    var studentIDs: [String] = []
    var legacyStudentLessonID: String?
    var trackID: String? = nil
    var trackStepID: String? = nil

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
        trackID: String? = nil,
        trackStepID: String? = nil,
        lessonTitleSnapshot: String? = nil,
        lessonSubtitleSnapshot: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.presentedAt = presentedAt
        self.lessonID = lessonID
        self.studentIDs = studentIDs
        self.legacyStudentLessonID = legacyStudentLessonID
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.lessonTitleSnapshot = lessonTitleSnapshot
        self.lessonSubtitleSnapshot = lessonSubtitleSnapshot
    }

    /// Convenience: map string IDs to UUIDs, dropping invalid values.
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }
    
    // Inverse relationship for Note.presentation
    @Relationship(deleteRule: .cascade, inverse: \Note.presentation) var unifiedNotes: [Note]? = []
}

#if DEBUG
extension Presentation {
    var debugDescription: String {
        let count = studentIDs.count
        return "Presentation(id=\(id), lessonID=\(lessonID.prefix(8))…, students=\(count), presentedAt=\(presentedAt))"
    }
}
#endif
