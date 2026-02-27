import Foundation
import SwiftData

/// StudentTrackEnrollment model representing a student's enrollment in a track.
/// Uses CloudKit-safe ID strings to avoid relationship complications.
@Model
final class StudentTrackEnrollment: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()
    
    /// Creation timestamp
    var createdAt: Date = Date()
    
    /// Student ID stored as UUID string (student.id.uuidString)
    var studentID: String = ""
    
    /// Track ID stored as UUID string (track.id.uuidString)
    var trackID: String = ""
    
    /// Optional start date for the enrollment
    var startedAt: Date? = nil
    
    /// Whether this enrollment is currently active
    var isActive: Bool = true
    
    @Relationship(deleteRule: .cascade, inverse: \Note.studentTrackEnrollment) var richNotes: [Note]? = []
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        studentID: String = "",
        trackID: String = "",
        startedAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.studentID = studentID
        self.trackID = trackID
        self.startedAt = startedAt
        self.isActive = isActive
        self.richNotes = []
    }
}

