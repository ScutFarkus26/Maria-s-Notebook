// BackupMigrationManifest.swift
// Central documentation and handling of backup format version changes

import Foundation

/// Central manifest documenting all backup format version changes and migrations.
/// This serves as the single source of truth for schema evolution.
public enum BackupMigrationManifest {

    // MARK: - Format Version History

    /// Documentation of format version 7 (current and only supported version)
    public static let versionHistory: [FormatVersionInfo] = [
        FormatVersionInfo(
            version: 7,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 2, day: 22).date!,
            description: "Current backup format without legacy WorkPlanItem compatibility",
            changes: [
                "LZFSE compression for efficient storage",
                "AES-GCM encryption with HKDF-SHA256 key derivation",
                "SHA256 checksum validation",
                "Deterministic JSON encoding with .sortedKeys",
                "Project entities for group work tracking",
                "Removed legacy WorkPlanItem payload field and restore handling"
            ],
            breakingChanges: [],
            migrationNotes: "This is the only supported backup format. Older backup formats (v1-v6) are not supported."
        )
    ]

    /// Current format version
    public static var currentVersion: Int {
        BackupFile.formatVersion
    }

    /// Gets version info for a specific version
    public static func info(for version: Int) -> FormatVersionInfo? {
        versionHistory.first { $0.version == version }
    }

    /// Checks if a version is compatible with current version
    public static func isCompatible(version: Int) -> VersionCompatibility {
        if version == currentVersion {
            return .compatible
        }
        if version > currentVersion {
            return .futureVersion(version)
        }
        return .invalid
    }

    // MARK: - Types

    public struct FormatVersionInfo: Identifiable, Sendable {
        public let id: Int
        public let version: Int
        public let releaseDate: Date
        public let description: String
        public let changes: [String]
        public let breakingChanges: [String]
        public let migrationNotes: String?

        public init(
            version: Int,
            releaseDate: Date,
            description: String,
            changes: [String],
            breakingChanges: [String],
            migrationNotes: String?
        ) {
            self.id = version
            self.version = version
            self.releaseDate = releaseDate
            self.description = description
            self.changes = changes
            self.breakingChanges = breakingChanges
            self.migrationNotes = migrationNotes
        }

        public var hasBreakingChanges: Bool {
            !breakingChanges.isEmpty
        }

        public var formattedReleaseDate: String {
            releaseDate.formatted(date: .abbreviated, time: .omitted)
        }
    }

    public struct Migration: Identifiable, Sendable {
        public let id = UUID()
        public let fromVersion: Int
        public let toVersion: Int
        public let description: String
        public let breakingChanges: [String]
        public let migrationNotes: String?
    }

    public enum VersionCompatibility: Sendable {
        case compatible
        case futureVersion(Int)
        case invalid

        public var isCompatible: Bool {
            if case .compatible = self { return true }
            return false
        }

        public var message: String {
            switch self {
            case .compatible:
                return "Format version is compatible."
            case .futureVersion(let version):
                return "Backup was created with a newer app version "
                    + "(format v\(version)). Please update the app."
            case .invalid:
                let ver = BackupMigrationManifest.currentVersion
                return "Unsupported backup format version. "
                    + "Only format v\(ver) is supported."
            }
        }
    }
}

// MARK: - Entity Schema Changes

extension BackupMigrationManifest {

    /// Documents entity schemas in the current format (v6)
    public enum EntitySchemaChanges {

        // MARK: - Student

        public static let studentChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Student",
                change: "Fields: id, firstName, lastName, birthday, "
                    + "level, dateStarted, nextLessons, manualOrder"
            )
        ]

        // MARK: - Lesson

        public static let lessonChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Lesson",
                change: "Fields: id, name, subject, group, "
                    + "orderInGroup, subheading, writeUp, "
                    + "pagesFileRelativePath"
            )
        ]

        // MARK: - Note

        public static let noteChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Note",
                change: "Fields: id, createdAt, updatedAt, body, "
                    + "isPinned, scope (JSON), lessonID, imagePath"
            )
        ]

        // MARK: - Project

        public static let projectChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Project",
                change: "Fields: id, createdAt, title, bookTitle, "
                    + "memberStudentIDs"
            ),
            EntityChange(
                version: 6, entity: "ProjectSession",
                change: "Fields: id, createdAt, projectID, "
                    + "meetingDate, chapterOrPages, notes, "
                    + "agendaItemsJSON, templateWeekID"
            ),
            EntityChange(
                version: 6, entity: "ProjectRole",
                change: "Fields: id, createdAt, projectID, title, "
                    + "summary, instructions"
            ),
            EntityChange(
                version: 6, entity: "ProjectTemplateWeek",
                change: "Fields: id, createdAt, projectID, "
                    + "weekIndex, readingRange, agendaItemsJSON, "
                    + "linkedLessonIDsJSON, workInstructions"
            ),
            EntityChange(
                version: 6, entity: "ProjectWeekRoleAssignment",
                change: "Fields: id, createdAt, weekID, "
                    + "studentID, roleID"
            ),
            EntityChange(
                version: 6, entity: "ProjectAssignmentTemplate",
                change: "Fields: id, createdAt, projectID, title, "
                    + "instructions, isShared, "
                    + "defaultLinkedLessonID"
            )
        ]

        // MARK: - Attendance

        public static let attendanceChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "AttendanceRecord",
                change: "Fields: id, studentID, date, status, "
                    + "absenceReason, note"
            )
        ]

    }

    public struct EntityChange: Identifiable, Sendable {
        public let id = UUID()
        public let version: Int
        public let entity: String
        public let change: String
    }
}

// MARK: - Payload Field Documentation

extension BackupMigrationManifest {

    /// Documents all payload fields in the current format
    public static let payloadFields: [PayloadField] = [
        // Core entities
        PayloadField(name: "items", introducedIn: 6, description: "Legacy items array (unused)"),
        PayloadField(name: "students", introducedIn: 6, description: "Student records"),
        PayloadField(name: "lessons", introducedIn: 6, description: "Lesson definitions"),
        PayloadField(name: "lessonAssignments", introducedIn: 6, description: "Unified lesson assignments"),
        PayloadField(name: "notes", introducedIn: 6, description: "Notes and observations"),
        PayloadField(name: "nonSchoolDays", introducedIn: 6, description: "Calendar non-school days"),
        PayloadField(name: "schoolDayOverrides", introducedIn: 6, description: "Calendar school day overrides"),

        // Meetings
        PayloadField(name: "studentMeetings", introducedIn: 6, description: "Student meeting records"),

        // Community
        PayloadField(name: "communityTopics", introducedIn: 6, description: "Community discussion topics"),
        PayloadField(name: "proposedSolutions", introducedIn: 6, description: "Solutions for community topics"),
        PayloadField(name: "communityAttachments", introducedIn: 6, description: "Attachments for community topics"),

        // Attendance and work
        PayloadField(name: "attendance", introducedIn: 6, description: "Attendance records"),
        PayloadField(name: "workCompletions", introducedIn: 6, description: "Work completion records"),

        // Projects
        PayloadField(name: "projects", introducedIn: 6, description: "Project entities for group work"),
        PayloadField(name: "projectAssignmentTemplates", introducedIn: 6, description: "Project assignment templates"),
        PayloadField(name: "projectSessions", introducedIn: 6, description: "Project session records"),
        PayloadField(name: "projectRoles", introducedIn: 6, description: "Project role definitions"),
        PayloadField(name: "projectTemplateWeeks", introducedIn: 6, description: "Project weekly templates"),
        PayloadField(
            name: "projectWeekRoleAssignments",
            introducedIn: 6,
            description: "Project role assignments per week"
        ),

        // Preferences
        PayloadField(name: "preferences", introducedIn: 6, description: "App preferences dictionary")
    ]

    public struct PayloadField: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let introducedIn: Int
        public let removedIn: Int?
        public let description: String

        public init(name: String, introducedIn: Int, removedIn: Int? = nil, description: String) {
            self.name = name
            self.introducedIn = introducedIn
            self.removedIn = removedIn
            self.description = description
        }

        public var isActive: Bool {
            removedIn == nil
        }

        public var versionRange: String {
            if let removed = removedIn {
                return "v\(introducedIn) - v\(removed - 1)"
            }
            return "v\(introducedIn)+"
        }
    }
}
