// BackupDiffTypes.swift
// Standalone types used by BackupDiffService

import Foundation

/// Represents the difference between two backups or between a backup and current data
public struct BackupDiff: Sendable {
    public let sourceDescription: String
    public let targetDescription: String
    public let entityDiffs: [EntityDiff]
    public let createdAt: Date

    public var totalAdded: Int {
        entityDiffs.reduce(0) { $0 + $1.added.count }
    }

    public var totalRemoved: Int {
        entityDiffs.reduce(0) { $0 + $1.removed.count }
    }

    public var totalModified: Int {
        entityDiffs.reduce(0) { $0 + $1.modified.count }
    }

    public var hasChanges: Bool {
        totalAdded > 0 || totalRemoved > 0 || totalModified > 0
    }

    public var summary: String {
        if !hasChanges {
            return "No changes"
        }
        var parts: [String] = []
        if totalAdded > 0 { parts.append("+\(totalAdded) added") }
        if totalRemoved > 0 { parts.append("-\(totalRemoved) removed") }
        if totalModified > 0 { parts.append("~\(totalModified) modified") }
        return parts.joined(separator: ", ")
    }
}

/// Differences for a specific entity type
public struct EntityDiff: Identifiable, Sendable {
    public let id = UUID()
    public let entityType: String
    public let added: [EntityChange]
    public let removed: [EntityChange]
    public let modified: [EntityModification]

    public var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !modified.isEmpty
    }

    public var changeCount: Int {
        added.count + removed.count + modified.count
    }
}

/// Represents an added or removed entity
public struct EntityChange: Identifiable, Sendable {
    public let id: UUID
    public let entityID: UUID
    public let description: String
    public let timestamp: Date?
}

/// Represents a modified entity with field-level changes
public struct EntityModification: Identifiable, Sendable {
    public let id: UUID
    public let entityID: UUID
    public let description: String
    public let fieldChanges: [FieldChange]
}

/// Represents a change to a specific field
public struct FieldChange: Identifiable, Sendable {
    public let id = UUID()
    public let fieldName: String
    public let oldValue: String
    public let newValue: String
}
