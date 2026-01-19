// BackupMigrationManifest.swift
// Central documentation and handling of backup format version changes

import Foundation

/// Central manifest documenting all backup format version changes and migrations.
/// This serves as the single source of truth for schema evolution.
public enum BackupMigrationManifest {

    // MARK: - Format Version History

    /// Documentation of all format version changes
    public static let versionHistory: [FormatVersionInfo] = [
        FormatVersionInfo(
            version: 1,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!,
            description: "Initial backup format",
            changes: [
                "Initial schema with basic entities",
                "Uncompressed JSON payload",
                "No encryption support"
            ],
            breakingChanges: [],
            migrationNotes: nil
        ),
        FormatVersionInfo(
            version: 2,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 3, day: 1).date!,
            description: "Added BookClub entities",
            changes: [
                "Added BookClub, BookClubSession, BookClubRole entities",
                "Added BookClubTemplateWeek, BookClubWeekRoleAssignment",
                "Added BookClubAssignmentTemplate"
            ],
            breakingChanges: [],
            migrationNotes: "No migration needed - new entities only"
        ),
        FormatVersionInfo(
            version: 3,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 5, day: 1).date!,
            description: "Added attendance and work completion records",
            changes: [
                "Added AttendanceRecord entity",
                "Added WorkCompletionRecord entity",
                "Backward compatible arrays in payload"
            ],
            breakingChanges: [],
            migrationNotes: "Missing arrays default to empty on import"
        ),
        FormatVersionInfo(
            version: 4,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 8, day: 1).date!,
            description: "Added encryption support",
            changes: [
                "Added encryptedPayload field",
                "AES-GCM encryption with HKDF-SHA256 key derivation",
                "Salt prepended to encrypted data (32 bytes)"
            ],
            breakingChanges: [],
            migrationNotes: "Encrypted backups require password for restore"
        ),
        FormatVersionInfo(
            version: 5,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 10, day: 1).date!,
            description: "Checksum validation and deterministic encoding",
            changes: [
                "Added SHA256 checksum in manifest",
                "Deterministic JSON encoding with .sortedKeys",
                "Checksum validation on import"
            ],
            breakingChanges: [
                "Old backups may fail checksum validation (use bypass option)"
            ],
            migrationNotes: "Enable 'Allow checksum bypass' for pre-v5 backups"
        ),
        FormatVersionInfo(
            version: 6,
            releaseDate: DateComponents(calendar: .current, year: 2024, month: 12, day: 1).date!,
            description: "Compression and Project rename",
            changes: [
                "Added LZFSE compression support",
                "Added compressedPayload field",
                "Renamed BookClub -> Project (with backward compatibility)",
                "Added compression field in manifest",
                "Removed ScopedNote entity (migrated to Note)",
                "Removed MeetingNote entity"
            ],
            breakingChanges: [
                "ScopedNote data is dropped during restore (already migrated)",
                "MeetingNote data is dropped during restore"
            ],
            migrationNotes: """
                BookClub entities automatically converted to Project entities during import.
                Legacy keys (bookClubs, bookClubSessions, etc.) supported for backward compatibility.
                """
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
        if version > currentVersion {
            return .futureVersion(version)
        }
        if version < 1 {
            return .invalid
        }
        return .compatible
    }

    /// Gets migration path from one version to another
    public static func migrationPath(from: Int, to: Int) -> [Migration] {
        guard from < to else { return [] }

        var migrations: [Migration] = []
        for version in (from + 1)...to {
            if let info = info(for: version), !info.breakingChanges.isEmpty {
                migrations.append(Migration(
                    fromVersion: version - 1,
                    toVersion: version,
                    description: info.description,
                    breakingChanges: info.breakingChanges,
                    migrationNotes: info.migrationNotes
                ))
            }
        }
        return migrations
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
                return "Backup was created with a newer app version (format v\(version)). Please update the app."
            case .invalid:
                return "Invalid backup format version."
            }
        }
    }
}

// MARK: - Entity Schema Changes

extension BackupMigrationManifest {

    /// Documents entity-specific schema changes for reference
    public enum EntitySchemaChanges {

        // MARK: - Student

        public static let studentChanges: [EntityChange] = [
            EntityChange(version: 1, entity: "Student", change: "Initial: id, firstName, lastName, birthday, level"),
            EntityChange(version: 2, entity: "Student", change: "Added: dateStarted, nextLessons array"),
            EntityChange(version: 3, entity: "Student", change: "Added: manualOrder for sorting")
        ]

        // MARK: - Lesson

        public static let lessonChanges: [EntityChange] = [
            EntityChange(version: 1, entity: "Lesson", change: "Initial: id, name, subject, group, orderInGroup"),
            EntityChange(version: 2, entity: "Lesson", change: "Added: subheading, writeUp"),
            EntityChange(version: 3, entity: "Lesson", change: "Added: pagesFileRelativePath (optional)")
        ]

        // MARK: - Note

        public static let noteChanges: [EntityChange] = [
            EntityChange(version: 1, entity: "ScopedNote", change: "Initial: id, createdAt, updatedAt, body, scope"),
            EntityChange(version: 5, entity: "ScopedNote", change: "Added: studentLessonID, workID, presentationID"),
            EntityChange(version: 6, entity: "Note", change: "Replaced ScopedNote with unified Note entity"),
            EntityChange(version: 6, entity: "Note", change: "Fields: id, createdAt, updatedAt, body, isPinned, scope (JSON), lessonID, imagePath")
        ]

        // MARK: - Project (formerly BookClub)

        public static let projectChanges: [EntityChange] = [
            EntityChange(version: 2, entity: "BookClub", change: "Initial: id, createdAt, title, bookTitle, memberStudentIDs"),
            EntityChange(version: 6, entity: "Project", change: "Renamed from BookClub; same fields"),
            EntityChange(version: 6, entity: "ProjectSession", change: "Renamed from BookClubSession"),
            EntityChange(version: 6, entity: "ProjectRole", change: "Renamed from BookClubRole"),
            EntityChange(version: 6, entity: "ProjectTemplateWeek", change: "Renamed from BookClubTemplateWeek"),
            EntityChange(version: 6, entity: "ProjectWeekRoleAssignment", change: "Renamed from BookClubWeekRoleAssignment"),
            EntityChange(version: 6, entity: "ProjectAssignmentTemplate", change: "Renamed from BookClubAssignmentTemplate")
        ]

        // MARK: - Attendance

        public static let attendanceChanges: [EntityChange] = [
            EntityChange(version: 3, entity: "AttendanceRecord", change: "Initial: id, studentID, date, status"),
            EntityChange(version: 4, entity: "AttendanceRecord", change: "Added: absenceReason, note"),
            EntityChange(version: 5, entity: "AttendanceRecord", change: "Changed: studentID from UUID to String")
        ]

        public struct EntityChange: Identifiable, Sendable {
            public let id = UUID()
            public let version: Int
            public let entity: String
            public let change: String
        }
    }
}

// MARK: - Payload Field Documentation

extension BackupMigrationManifest {

    /// Documents all payload fields and their introduction versions
    public static let payloadFields: [PayloadField] = [
        // Core entities
        PayloadField(name: "items", introducedIn: 1, description: "Legacy items array (unused)"),
        PayloadField(name: "students", introducedIn: 1, description: "Student records"),
        PayloadField(name: "lessons", introducedIn: 1, description: "Lesson definitions"),
        PayloadField(name: "studentLessons", introducedIn: 1, description: "Lesson assignments to students"),
        PayloadField(name: "workPlanItems", introducedIn: 1, description: "Scheduled work items"),
        PayloadField(name: "scopedNotes", introducedIn: 1, removedIn: 6, description: "Legacy scoped notes (migrated to notes)"),
        PayloadField(name: "notes", introducedIn: 6, description: "Unified notes entity"),
        PayloadField(name: "nonSchoolDays", introducedIn: 1, description: "Calendar non-school days"),
        PayloadField(name: "schoolDayOverrides", introducedIn: 1, description: "Calendar school day overrides"),

        // Meetings and presentations
        PayloadField(name: "studentMeetings", introducedIn: 1, description: "Student meeting records"),
        PayloadField(name: "presentations", introducedIn: 1, description: "Lesson presentation records"),

        // Community
        PayloadField(name: "communityTopics", introducedIn: 1, description: "Community discussion topics"),
        PayloadField(name: "proposedSolutions", introducedIn: 1, description: "Solutions for community topics"),
        PayloadField(name: "meetingNotes", introducedIn: 1, removedIn: 6, description: "Legacy meeting notes (removed)"),
        PayloadField(name: "communityAttachments", introducedIn: 1, description: "Attachments for community topics"),

        // Attendance and work
        PayloadField(name: "attendance", introducedIn: 3, description: "Attendance records"),
        PayloadField(name: "workCompletions", introducedIn: 3, description: "Work completion records"),

        // Projects (formerly BookClubs)
        PayloadField(name: "projects", introducedIn: 6, description: "Project entities (renamed from bookClubs)"),
        PayloadField(name: "projectAssignmentTemplates", introducedIn: 6, description: "Project assignment templates"),
        PayloadField(name: "projectSessions", introducedIn: 6, description: "Project session records"),
        PayloadField(name: "projectRoles", introducedIn: 6, description: "Project role definitions"),
        PayloadField(name: "projectTemplateWeeks", introducedIn: 6, description: "Project weekly templates"),
        PayloadField(name: "projectWeekRoleAssignments", introducedIn: 6, description: "Project role assignments per week"),

        // Legacy BookClub keys (for backward compatibility)
        PayloadField(name: "bookClubs", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projects'"),
        PayloadField(name: "bookClubAssignmentTemplates", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projectAssignmentTemplates'"),
        PayloadField(name: "bookClubSessions", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projectSessions'"),
        PayloadField(name: "bookClubRoles", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projectRoles'"),
        PayloadField(name: "bookClubTemplateWeeks", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projectTemplateWeeks'"),
        PayloadField(name: "bookClubWeekRoleAssignments", introducedIn: 2, removedIn: 6, description: "Legacy: now 'projectWeekRoleAssignments'"),

        // Preferences
        PayloadField(name: "preferences", introducedIn: 1, description: "App preferences dictionary")
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
