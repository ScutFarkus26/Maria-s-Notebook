import Foundation
import SwiftData

/// TrackStep model representing a single step in a Track's progression sequence.
/// Steps are ordered by orderIndex to ensure deterministic progression through the track.
@Model
final class TrackStep: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()
    
    /// The track this step belongs to (plain property, relationship defined on Track.steps)
    var track: Track? = nil
    
    /// Order index within the track (0-based, lower numbers come first)
    /// Used to ensure deterministic ordering of steps
    var orderIndex: Int = 0
    
    /// Reference to the lesson template (Lesson) for this step
    var lessonTemplateID: UUID? = nil
    
    /// Creation timestamp
    var createdAt: Date = Date()
    
    init(
        id: UUID = UUID(),
        track: Track? = nil,
        orderIndex: Int = 0,
        lessonTemplateID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.track = track
        self.orderIndex = orderIndex
        self.lessonTemplateID = lessonTemplateID
        self.createdAt = createdAt
    }
}

