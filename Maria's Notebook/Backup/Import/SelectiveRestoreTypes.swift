// SelectiveRestoreTypes.swift
// Type definitions for selective backup restoration

import Foundation

// MARK: - Restorable Entity Types

/// Entity types that can be selectively restored
public enum RestorableEntityType: String, CaseIterable, Identifiable, Sendable {
    case students = "Students"
    case lessons = "Lessons"
    case notes = "Notes"
    case calendar = "Calendar (Non-School Days & Overrides)"
    case meetings = "Student Meetings"
    case community = "Community Topics & Solutions"
    case attendance = "Attendance Records"
    case workCompletions = "Work Completion Records"
    case projects = "Projects"

    public var id: String { rawValue }

    public var description: String { rawValue }

    public var systemImage: String {
        switch self {
        case .students: return "person.3"
        case .lessons: return "book"
        case .notes: return "note.text"
        case .calendar: return "calendar"
        case .meetings: return "person.2.wave.2"
        case .community: return "bubble.left.and.bubble.right"
        case .attendance: return "checkmark.circle"
        case .workCompletions: return "checkmark.square"
        case .projects: return "folder"
        }
    }

    /// Dependencies that must be restored together
    public var dependencies: [RestorableEntityType] {
        switch self {
        case .community: return []
        case .notes: return [.lessons]
        case .workCompletions: return []
        case .projects: return [.students]
        default: return []
        }
    }
}

// MARK: - Selective Restore Options

/// Options for selective restore
public struct SelectiveRestoreOptions: Sendable {
    public var entityTypes: Set<RestorableEntityType>
    public var mode: BackupService.RestoreMode
    public var includeDependencies: Bool

    public init(
        entityTypes: Set<RestorableEntityType>,
        mode: BackupService.RestoreMode = .merge,
        includeDependencies: Bool = true
    ) {
        self.entityTypes = entityTypes
        self.mode = mode
        self.includeDependencies = includeDependencies
    }

    /// Returns the full set of entity types including dependencies
    public var resolvedEntityTypes: Set<RestorableEntityType> {
        guard includeDependencies else { return entityTypes }

        var resolved = entityTypes
        for type in entityTypes {
            for dependency in type.dependencies {
                resolved.insert(dependency)
            }
        }
        return resolved
    }
}

// MARK: - Selective Restore Preview

/// Result of selective restore preview
public struct SelectiveRestorePreview: Sendable {
    public var entityCounts: [RestorableEntityType: Int]
    public var warnings: [String]
    public var missingDependencies: [RestorableEntityType]

    public var totalEntities: Int {
        entityCounts.values.reduce(0, +)
    }
}

// MARK: - Selective Restore Result

/// Result of selective restore operation
public struct SelectiveRestoreResult: Sendable {
    public var importedCounts: [RestorableEntityType: Int]
    public var skippedCounts: [RestorableEntityType: Int]
    public var warnings: [String]

    public var totalImported: Int {
        importedCounts.values.reduce(0, +)
    }

    public var totalSkipped: Int {
        skippedCounts.values.reduce(0, +)
    }
}
