import Foundation
import SwiftData

/// Represents a track derived from a lesson group.
/// Each (subject, group) combination can be marked as a track.
/// Tracks can be sequential (order matters) or unordered (group of lessons).
@Model
final class GroupTrack: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()
    
    /// Subject name (e.g., "Math", "Language")
    var subject: String = ""
    
    /// Group name (e.g., "Decimal System", "Addition")
    var group: String = ""
    
    /// Whether this is a sequential track (order matters) or just a group
    var isSequential: Bool = true
    
    /// Whether this group is explicitly disabled as a track.
    /// If false or nil, the group is a track (default behavior).
    /// If true, the user has explicitly unchecked "Use as Track".
    var isExplicitlyDisabled: Bool = false
    
    /// Creation timestamp
    var createdAt: Date = Date()
    
    init(
        id: UUID = UUID(),
        subject: String,
        group: String,
        isSequential: Bool = true,
        isExplicitlyDisabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject.trimmed()
        self.group = group.trimmed()
        self.isSequential = isSequential
        self.isExplicitlyDisabled = isExplicitlyDisabled
        self.createdAt = createdAt
    }
    
    /// Computed property: Unique identifier for this (subject, group) combination
    @Transient
    var groupKey: String {
        "\(subject)|\(group)"
    }
}
