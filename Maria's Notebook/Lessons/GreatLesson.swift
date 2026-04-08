// GreatLesson.swift
// The Five Great Lessons of AMI Montessori Elementary curriculum.
// Used to connect individual lessons to cosmic education themes.

import SwiftUI
import CoreData

enum GreatLesson: String, CaseIterable, Identifiable, Codable {
    case comingOfUniverse
    case comingOfLife
    case comingOfHumans
    case communicationInSigns
    case storyOfNumbers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comingOfUniverse: return "Coming of the Universe"
        case .comingOfLife: return "Coming of Life"
        case .comingOfHumans: return "Coming of Humans"
        case .communicationInSigns: return "Communication in Signs"
        case .storyOfNumbers: return "Story of Numbers"
        }
    }

    var shortName: String {
        switch self {
        case .comingOfUniverse: return "Universe"
        case .comingOfLife: return "Life"
        case .comingOfHumans: return "Humans"
        case .communicationInSigns: return "Signs"
        case .storyOfNumbers: return "Numbers"
        }
    }

    var icon: String {
        switch self {
        case .comingOfUniverse: return "sparkles"
        case .comingOfLife: return "leaf"
        case .comingOfHumans: return "figure.stand"
        case .communicationInSigns: return "character.book.closed"
        case .storyOfNumbers: return "number"
        }
    }

    var color: Color {
        switch self {
        case .comingOfUniverse: return .indigo
        case .comingOfLife: return .green
        case .comingOfHumans: return .orange
        case .communicationInSigns: return .blue
        case .storyOfNumbers: return .purple
        }
    }

    var description: String {
        switch self {
        case .comingOfUniverse:
            return "The story of how the universe, Earth, and physical laws came to be"
        case .comingOfLife:
            return "The story of the emergence and evolution of life on Earth"
        case .comingOfHumans:
            return "The story of early humans and the development of civilization"
        case .communicationInSigns:
            return "The story of written language and the development of the alphabet"
        case .storyOfNumbers:
            return "The story of mathematics and how humans developed number systems"
        }
    }

    /// Primary subjects that relate to this Great CDLesson
    var relatedSubjects: [String] {
        switch self {
        case .comingOfUniverse:
            return ["Science", "Geography", "History"]
        case .comingOfLife:
            return ["Botany", "Zoology", "Science"]
        case .comingOfHumans:
            return ["History", "Geography"]
        case .communicationInSigns:
            return ["Language", "Language Arts", "Reading", "Writing"]
        case .storyOfNumbers:
            return ["Math", "Mathematics", "Geometry"]
        }
    }

    // MARK: - Resolution

    /// Returns all Great Lessons for a given lesson.
    /// Prefers explicit tag (authoritative), falls back to subject-based heuristic.
    /// A lesson may map to multiple Great Lessons (e.g., Science → Universe + Life).
    /// Returns empty array if no mapping exists.
    static func resolve(for lesson: CDLesson) -> [GreatLesson] {
        if let explicit = lesson.greatLesson {
            return [explicit]
        }
        let normalized = lesson.subject.normalizedForComparison()
        return GreatLesson.allCases.filter { gl in
            gl.relatedSubjects.contains { $0.normalizedForComparison() == normalized }
        }
    }
}
