import Foundation
import SwiftData

/// Track model for deterministic progression through a sequence of lessons.
/// A Track represents an ordered sequence of lesson steps (TrackSteps) that can be followed
/// to progress through a curriculum in a structured way.
@Model
final class Track: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()
    
    /// Track title/name
    var title: String = ""
    
    /// Creation timestamp
    var createdAt: Date = Date()
    
    /// Ordered steps in this track (cascade delete when track is deleted)
    /// Optional to satisfy CloudKit relationship requirements
    @Relationship(deleteRule: .cascade, inverse: \TrackStep.track)
    var steps: [TrackStep]? = []
    
    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.steps = nil
    }
}
