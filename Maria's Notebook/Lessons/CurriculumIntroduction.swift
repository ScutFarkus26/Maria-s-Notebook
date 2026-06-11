// Maria's Notebook/Lessons/CurriculumIntroduction.swift
//
// Lightweight model for album and sequence introductions.
// Stored as JSON in the app's Documents directory, not in SwiftData.

import Foundation

/// Represents an introduction for either an album (area-level) or a sequence within a area.
struct CurriculumIntroduction: Codable, Identifiable, Equatable {
    /// Unique identifier for this introduction
    var id: UUID

    /// The area this introduction belongs to (e.g., "Math", "Language")
    var area: String

    /// The sequence within the area. If nil, this is an album-level introduction.
    var sequence: String?

    /// The markdown content of the introduction
    var content: String

    /// Optional metadata
    var prerequisites: String?
    var ageRange: String?

    /// Last modified timestamp
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        area: String,
        sequence: String? = nil,
        content: String,
        prerequisites: String? = nil,
        ageRange: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.area = area
        self.sequence = sequence
        self.content = content
        self.prerequisites = prerequisites
        self.ageRange = ageRange
        self.modifiedAt = modifiedAt
    }

    /// Returns true if this is an album-level introduction (no sequence specified)
    var isAlbumLevel: Bool {
        sequence == nil || sequence?.trimmingCharacters(in: .whitespaces).isEmpty == true
    }

    /// Display title for the introduction
    var displayTitle: String {
        if let sequence, !sequence.isEmpty {
            return sequence
        }
        return "\(area) Album"
    }
}
