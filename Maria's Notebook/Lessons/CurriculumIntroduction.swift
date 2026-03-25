// Maria's Notebook/Lessons/CurriculumIntroduction.swift
//
// Lightweight model for album and group introductions.
// Stored as JSON in the app's Documents directory, not in SwiftData.

import Foundation

/// Represents an introduction for either an album (subject-level) or a group within a subject.
struct CurriculumIntroduction: Codable, Identifiable, Equatable {
    /// Unique identifier for this introduction
    var id: UUID

    /// The subject this introduction belongs to (e.g., "Math", "Language")
    var subject: String

    /// The group within the subject. If nil, this is an album-level introduction.
    var group: String?

    /// The markdown content of the introduction
    var content: String

    /// Optional metadata
    var prerequisites: String?
    var ageRange: String?

    /// Last modified timestamp
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        subject: String,
        group: String? = nil,
        content: String,
        prerequisites: String? = nil,
        ageRange: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.group = group
        self.content = content
        self.prerequisites = prerequisites
        self.ageRange = ageRange
        self.modifiedAt = modifiedAt
    }

    /// Returns true if this is an album-level introduction (no group specified)
    var isAlbumLevel: Bool {
        group == nil || group?.trimmingCharacters(in: .whitespaces).isEmpty == true
    }

    /// Display title for the introduction
    var displayTitle: String {
        if let group, !group.isEmpty {
            return group
        }
        return "\(subject) Album"
    }
}

/// Container for storing multiple introductions
struct CurriculumIntroductionLibrary: Codable {
    var introductions: [CurriculumIntroduction]
    var version: Int

    init(introductions: [CurriculumIntroduction] = [], version: Int = 1) {
        self.introductions = introductions
        self.version = version
    }
}
