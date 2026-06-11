// BackupMigrationManifest.swift
// Central documentation and handling of backup format version changes

import Foundation

/// Central manifest documenting all backup format version changes and migrations.
/// This serves as the single source of truth for schema evolution.
public enum BackupMigrationManifest {

    // MARK: - Format Version History

    /// Historical record of backup format versions that existed before the
    /// current restore pipeline was simplified to the latest format only.
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
                "Tracks: CDTrackEntity, CDTrackStepEntity, CDStudentTrackEnrollmentEntity, CDSequenceTrack",
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
            description: "Adds Going Out, Classroom Jobs, Calendar Notes, and more",
            changes: [
                "CDGoingOut and CDGoingOutChecklistItem",
                "CDClassroomJob and CDJobAssignment",
                "CDCalendarNote, CDScheduledMeeting"
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
        ),
        FormatVersionInfo(
            version: 14,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 4, day: 15).date!,
            description: "Adds CDMeetingWorkReview, CDStudentFocusItem, CDWorkModel.restingUntil",
            changes: [
                "CDMeetingWorkReview entity for tracking work discussed in meetings",
                "CDStudentFocusItem entity for structured focus carry-forward",
                "CDWorkModel.restingUntil for intentional rest (pauses aging)"
            ],
            breakingChanges: [],
            migrationNotes: "New optional arrays; older payloads decode these as nil."
        ),
        FormatVersionInfo(
            version: 15,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 5, day: 11).date!,
            description: "Adds CDInitiative entity and CDTodoItem.initiativeID " +
                "for the Planning section project manager",
            changes: [
                "CDInitiative entity for Things-style planning initiatives",
                "CDTodoItem.initiativeID String FK linking todos to initiatives"
            ],
            breakingChanges: [],
            migrationNotes: "Initiatives is a new optional array; older payloads decode this as nil. " +
                "CDTodoItem.initiativeID is optional and defaults to nil for older payloads."
        ),
        FormatVersionInfo(
            version: 16,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 5, day: 17).date!,
            description: "Renames lesson hierarchy from subject/group/subheading to area/sequence/section",
            changes: [
                "CDLesson.subject -> area, CDLesson.group -> sequence, " +
                    "CDLesson.subheading -> section, CDLesson.orderInGroup -> orderInSequence",
                "GroupTrack entity renamed to SequenceTrack; LessonGroupSettings renamed to LessonSequenceSettings",
                "CDLessonAssignment.lessonSubheadingSnapshot -> lessonSectionSnapshot",
                "Backup payload key groupTracks -> sequenceTracks"
            ],
            breakingChanges: ["Pre-v16 backups will not restore; payload keys and entity names changed."],
            migrationNotes: "Destructive rename of lesson hierarchy; the local store is wiped at upgrade time."
        ),
        FormatVersionInfo(
            version: 18,
            releaseDate: DateComponents(calendar: .current, year: 2026, month: 6, day: 3).date!,
            description: "Adds backup coverage for Stories, Book Club, Year Plan, and Day Pads",
            changes: [
                "CDDayPad (per-date scratchpad)",
                "CDYearPlanEntry and CDLessonSequenceSettings (year planning + progression)",
                "CDStory (Stories library)",
                "CDBookClubPacket, CDBookClubSession, CDBookClubMeeting (Book Club)"
            ],
            breakingChanges: [],
            migrationNotes: "New optional NDJSON entries on the v17 AEA format; older readers skip " +
                "unknown entities. Binary blobs (PDFs, thumbnails, covers) are excluded by design."
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

    /// Checks whether a backup version matches the current restore format.
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
                let max = BackupMigrationManifest.currentVersion
                return "Unsupported backup format version. "
                    + "Only version v\(max) is supported for restore."
            }
        }
    }
}
