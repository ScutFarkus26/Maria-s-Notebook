// BackupMigrationManifest.swift
// Central documentation and handling of backup format version changes

import Foundation

/// Central manifest documenting all backup format version changes and migrations.
/// This serves as the single source of truth for schema evolution.
public enum BackupMigrationManifest {

    // MARK: - Format Version History

    /// Complete history of all supported backup format versions (v5–v13).
    /// Versions prior to v5 are unsupported (no checksum enforcement).
    public static let versionHistory: [FormatVersionInfo] = [
        FormatVersionInfo(
            version: 5,
            releaseDate: DateComponents(calendar: .current, year: 2025, month: 10, day: 1).date!,
            description: "First checksummed format with deterministic JSON encoding",
            changes: [
                "SHA256 checksum validation enforced",
                "Deterministic JSON encoding with .sortedKeys",
                "Core entities: Students, Lessons, Notes, Calendar, Projects"
            ],
            breakingChanges: [],
            migrationNotes: "Minimum supported version. Inline payload (no compression)."
        ),
        FormatVersionInfo(
            version: 6,
            releaseDate: DateComponents(calendar: .current, year: 2025, month: 12, day: 1).date!,
            description: "Adds LZFSE compression support",
            changes: [
                "LZFSE compression for efficient storage",
                "AES-GCM encryption with HKDF-SHA256 key derivation",
                "Backward compatible with v5 inline payloads"
            ],
            breakingChanges: [],
            migrationNotes: "Backups from v5 are read via inline payload path."
        ),
        FormatVersionInfo(
            version: 7,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 1, day: 15).date!,
            description: "Removes legacy WorkPlanItem backward compatibility",
            changes: [
                "Removed legacy WorkPlanItem payload field and restore handling"
            ],
            breakingChanges: ["WorkPlanItem payloads from v1-v4 are no longer importable"],
            migrationNotes: "No payload schema change; only removes dead import code."
        ),
        FormatVersionInfo(
            version: 8,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 1, day: 25).date!,
            description: "Full entity coverage for Work, Tracks, Supplies, Todos, and more",
            changes: [
                "Work tracking: CDWorkCheckIn, CDWorkStep, CDWorkParticipantEntity, CDPracticeSession",
                "Lesson extras: CDLessonAttachment, CDLessonPresentation",
                "Templates: CDNoteTemplate, CDMeetingTemplate",
                "Reminders & Calendar: CDReminder, CDCalendarEvent",
                "Tracks: CDTrackEntity, CDTrackStepEntity, CDStudentTrackEnrollmentEntity, CDGroupTrack",
                "Documents, Supplies, Procedures, Schedules, Issues, Todos, Agenda"
            ],
            breakingChanges: [],
            migrationNotes: "New optional arrays; v5-v7 payloads decode these as nil."
        ),
        FormatVersionInfo(
            version: 10,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 2, day: 10).date!,
            description: "Adds CDSampleWork/CDSampleWorkStep, work step completionOutcome",
            changes: [
                "CDSampleWork and CDSampleWorkStep entities",
                "CDWorkStep completionOutcome field",
                "CDPracticeSession workStepID field"
            ],
            breakingChanges: [],
            migrationNotes: "New optional arrays; older payloads decode these as nil."
        ),
        FormatVersionInfo(
            version: 11,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 2, day: 20).date!,
            description: "Adds CDWorkModel, CDPlanningRecommendation, CDResource, CDNoteStudentLink",
            changes: [
                "CDWorkModel parent entity for work tracking",
                "CDPlanningRecommendation for AI-driven suggestions",
                "CDResource for educational resources",
                "CDNoteStudentLink junction table",
                "Removes LegacyPresentation backward compatibility"
            ],
            breakingChanges: ["LegacyPresentation format no longer importable"],
            migrationNotes: "New optional arrays; older payloads decode these as nil."
        ),
        FormatVersionInfo(
            version: 12,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 3, day: 5).date!,
            description: "Adds Going Out, Classroom Jobs, Transition Plans, Calendar Notes, and more",
            changes: [
                "CDGoingOut and CDGoingOutChecklistItem",
                "CDClassroomJob and CDJobAssignment",
                "CDTransitionPlan and CDTransitionChecklistItem",
                "CDCalendarNote, CDScheduledMeeting",
                "AlbumGroupOrder, AlbumGroupUIState (DTO-only stubs)"
            ],
            breakingChanges: [],
            migrationNotes: "New optional arrays; older payloads decode these as nil."
        ),
        FormatVersionInfo(
            version: 13,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 3, day: 20).date!,
            description: "Adds CDClassroomMembership for CloudKit sharing",
            changes: [
                "CDClassroomMembership entity for teacher-classroom role tracking"
            ],
            breakingChanges: [],
            migrationNotes: "New optional array; older payloads decode this as nil."
        )
    ]

    /// Minimum format version supported for import
    public static let minimumSupportedVersion = 5

    /// Current format version
    public static var currentVersion: Int {
        BackupFile.formatVersion
    }

    /// Gets version info for a specific version
    public static func info(for version: Int) -> FormatVersionInfo? {
        versionHistory.first { $0.version == version }
    }

    /// Checks if a version is compatible with current version.
    /// Versions v5 through currentVersion are supported — newer optional payload
    /// arrays simply decode as nil when restoring older backups.
    public static func isCompatible(version: Int) -> VersionCompatibility {
        if version >= minimumSupportedVersion && version <= currentVersion {
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
                let min = BackupMigrationManifest.minimumSupportedVersion
                let max = BackupMigrationManifest.currentVersion
                return "Unsupported backup format version. "
                    + "Versions v\(min) through v\(max) are supported."
            }
        }
    }
}

// MARK: - Entity Schema Changes

extension BackupMigrationManifest {

    /// Documents entity schemas across format versions (v5–v13)
    public enum EntitySchemaChanges {

        // MARK: - CDStudent

        public static let studentChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Student",
                change: "Fields: id, firstName, lastName, birthday, "
                    + "level, dateStarted, nextLessons, manualOrder"
            )
        ]

        // MARK: - CDLesson

        public static let lessonChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Lesson",
                change: "Fields: id, name, subject, group, "
                    + "orderInGroup, subheading, writeUp, "
                    + "pagesFileRelativePath"
            )
        ]

        // MARK: - CDNote

        public static let noteChanges: [EntityChange] = [
            EntityChange(
                version: 6, entity: "Note",
                change: "Fields: id, createdAt, updatedAt, body, "
                    + "isPinned, scope (JSON), lessonID, imagePath"
            )
        ]

        // MARK: - CDProject

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

    /// Documents all payload fields and the format version that introduced each
    public static let payloadFields: [PayloadField] = [
        // Core entities (v5+)
        PayloadField(name: "items", introducedIn: 5, description: "Legacy items array (unused)"),
        PayloadField(name: "students", introducedIn: 5, description: "CDStudent records"),
        PayloadField(name: "lessons", introducedIn: 5, description: "CDLesson definitions"),
        PayloadField(name: "lessonAssignments", introducedIn: 5, description: "Unified lesson assignments"),
        PayloadField(name: "notes", introducedIn: 5, description: "Notes and observations"),
        PayloadField(name: "nonSchoolDays", introducedIn: 5, description: "Calendar non-school days"),
        PayloadField(name: "schoolDayOverrides", introducedIn: 5, description: "Calendar school day overrides"),
        PayloadField(name: "studentMeetings", introducedIn: 5, description: "CDStudent meeting records"),
        PayloadField(name: "communityTopics", introducedIn: 5, description: "Community discussion topics"),
        PayloadField(name: "proposedSolutions", introducedIn: 5, description: "Solutions for community topics"),
        PayloadField(name: "communityAttachments", introducedIn: 5, description: "Attachments for community topics"),
        PayloadField(name: "attendance", introducedIn: 5, description: "Attendance records"),
        PayloadField(name: "workCompletions", introducedIn: 5, description: "Work completion records"),
        PayloadField(name: "projects", introducedIn: 5, description: "CDProject entities for group work"),
        PayloadField(name: "projectAssignmentTemplates", introducedIn: 5, description: "CDProject assignment templates"),
        PayloadField(name: "projectSessions", introducedIn: 5, description: "CDProject session records"),
        PayloadField(name: "projectRoles", introducedIn: 5, description: "CDProject role definitions"),
        PayloadField(name: "projectTemplateWeeks", introducedIn: 5, description: "CDProject weekly templates"),
        PayloadField(
            name: "projectWeekRoleAssignments",
            introducedIn: 5,
            description: "CDProject role assignments per week"
        ),
        PayloadField(name: "preferences", introducedIn: 5, description: "App preferences dictionary"),

        // Work tracking (v8+, optional arrays — nil when restoring older backups)
        PayloadField(name: "workCheckIns", introducedIn: 8, description: "CDWorkCheckIn records"),
        PayloadField(name: "workSteps", introducedIn: 8, description: "CDWorkStep records"),
        PayloadField(name: "workParticipants", introducedIn: 8, description: "CDWorkParticipantEntity records"),
        PayloadField(name: "practiceSessions", introducedIn: 8, description: "CDPracticeSession records"),
        PayloadField(name: "lessonAttachments", introducedIn: 8, description: "CDLessonAttachment records"),
        PayloadField(name: "lessonPresentations", introducedIn: 8, description: "CDLessonPresentation records"),
        PayloadField(name: "noteTemplates", introducedIn: 8, description: "CDNoteTemplate records"),
        PayloadField(name: "meetingTemplates", introducedIn: 8, description: "CDMeetingTemplate records"),
        PayloadField(name: "reminders", introducedIn: 8, description: "CDReminder records"),
        PayloadField(name: "calendarEvents", introducedIn: 8, description: "CDCalendarEvent records"),
        PayloadField(name: "tracks", introducedIn: 8, description: "CDTrackEntity records"),
        PayloadField(name: "trackSteps", introducedIn: 8, description: "CDTrackStepEntity records"),
        PayloadField(name: "studentTrackEnrollments", introducedIn: 8, description: "CDStudentTrackEnrollmentEntity records"),
        PayloadField(name: "groupTracks", introducedIn: 8, description: "CDGroupTrack records"),
        PayloadField(name: "documents", introducedIn: 8, description: "CDDocument metadata"),
        PayloadField(name: "supplies", introducedIn: 8, description: "CDSupply records"),
        PayloadField(name: "supplyTransactions", introducedIn: 8, description: "CDSupplyTransaction records (deprecated, ignored on import)"),
        PayloadField(name: "procedures", introducedIn: 8, description: "CDProcedure records"),
        PayloadField(name: "schedules", introducedIn: 8, description: "CDSchedule records"),
        PayloadField(name: "scheduleSlots", introducedIn: 8, description: "CDScheduleSlot records"),
        PayloadField(name: "issues", introducedIn: 8, description: "CDIssue records"),
        PayloadField(name: "issueActions", introducedIn: 8, description: "CDIssueAction records"),
        PayloadField(name: "developmentSnapshots", introducedIn: 8, description: "CDDevelopmentSnapshotEntity records"),
        PayloadField(name: "todoItems", introducedIn: 8, description: "CDTodoItem records"),
        PayloadField(name: "todoSubtasks", introducedIn: 8, description: "CDTodoSubtask records"),
        PayloadField(name: "todoTemplates", introducedIn: 8, description: "CDTodoTemplate records"),
        PayloadField(name: "todayAgendaOrders", introducedIn: 8, description: "CDTodayAgendaOrder records"),

        // Sample works (v10+)
        PayloadField(name: "sampleWorks", introducedIn: 10, description: "CDSampleWork records"),
        PayloadField(name: "sampleWorkSteps", introducedIn: 10, description: "CDSampleWorkStep records"),

        // Work models, planning, resources (v11+)
        PayloadField(name: "workModels", introducedIn: 11, description: "CDWorkModel parent entity"),
        PayloadField(name: "planningRecommendations", introducedIn: 11, description: "CDPlanningRecommendation records"),
        PayloadField(name: "resources", introducedIn: 11, description: "CDResource records"),
        PayloadField(name: "noteStudentLinks", introducedIn: 11, description: "CDNoteStudentLink junction records"),

        // Going Out, Classroom Jobs, Transitions (v12+)
        PayloadField(name: "goingOuts", introducedIn: 12, description: "CDGoingOut records"),
        PayloadField(name: "goingOutChecklistItems", introducedIn: 12, description: "CDGoingOutChecklistItem records"),
        PayloadField(name: "classroomJobs", introducedIn: 12, description: "CDClassroomJob records"),
        PayloadField(name: "jobAssignments", introducedIn: 12, description: "CDJobAssignment records"),
        PayloadField(name: "transitionPlans", introducedIn: 12, description: "CDTransitionPlan records"),
        PayloadField(name: "transitionChecklistItems", introducedIn: 12, description: "CDTransitionChecklistItem records"),
        PayloadField(name: "calendarNotes", introducedIn: 12, description: "CDCalendarNote records"),
        PayloadField(name: "scheduledMeetings", introducedIn: 12, description: "CDScheduledMeeting records"),
        PayloadField(name: "albumGroupOrders", introducedIn: 12, description: "AlbumGroupOrder DTO-only stubs"),
        PayloadField(name: "albumGroupUIStates", introducedIn: 12, description: "AlbumGroupUIState DTO-only stubs"),

        // Classroom sharing (v13+)
        PayloadField(name: "classroomMemberships", introducedIn: 13, description: "CDClassroomMembership records")
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
