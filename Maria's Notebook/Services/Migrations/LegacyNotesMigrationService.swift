import Foundation
import SwiftData

// MARK: - Legacy Notes Migration Service

/// Service responsible for migrating legacy string notes into Note objects.
/// Handles 9 different entity types that had legacy notes fields.
enum LegacyNotesMigrationService {

    // MARK: - StudentLesson Notes

    /// Migrate legacy string notes on StudentLesson into Note objects.
    /// For each StudentLesson with a non-empty `notes` string and empty `unifiedNotes`,
    /// creates a new Note object with the content and clears the legacy notes field.
    /// Idempotent: only processes StudentLessons that haven't been migrated yet.
    @MainActor
    static func migrateStudentLessonNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                !sl.notes.isEmpty
            }
        )
        let studentLessons = context.safeFetch(fetch)

        var migratedCount = 0

        for sl in studentLessons {
            // Double-check notes is not empty (predicate may not filter correctly in all cases)
            guard !sl.notes.isEmpty else { continue }
            // Check if unifiedNotes is empty - skip if already migrated
            guard (sl.unifiedNotes ?? []).isEmpty else { continue }

            // Determine scope from the first student ID if available
            let studentUUIDs = sl.studentIDs.compactMap { UUID(uuidString: $0) }
            let scope: NoteScope = studentUUIDs.count == 1 ? .student(studentUUIDs[0]) :
                                   studentUUIDs.count > 1 ? .students(studentUUIDs) : .all

            // Create a new Note object
            let note = Note(
                createdAt: sl.createdAt,
                body: sl.notes,
                scope: scope,
                category: .general,
                studentLesson: sl
            )

            context.insert(note)
            sl.notes = ""
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - WorkModel Notes

    /// Migrate legacy string notes on WorkModels into Note objects.
    /// For each WorkModel with a non-empty `notes` string and empty `unifiedNotes`,
    /// creates a new Note object with the content and clears the legacy notes field.
    /// Idempotent: only processes WorkModels that haven't been migrated yet.
    @MainActor
    static func migrateWorkNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { work in
                !work.notes.isEmpty
            }
        )
        let workModels = context.safeFetch(fetch)

        var migratedCount = 0

        for work in workModels {
            // Double-check notes is not empty (predicate may not filter correctly in all cases)
            guard !work.notes.isEmpty else { continue }
            // Check if unifiedNotes is empty (or nil) - skip if already migrated
            guard (work.unifiedNotes ?? []).isEmpty else { continue }

            // Create a new Note object using the content of work.notes
            let note = Note(
                createdAt: work.createdAt,
                body: work.notes,
                scope: .all,
                work: work
            )

            // Insert the note into the context
            context.insert(note)

            // Clear the old notes string to prevent re-migration
            work.notes = ""

            migratedCount += 1
        }

        // Save the context if any migrations occurred
        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - WorkCheckIn Notes

    /// Migrate legacy string notes on WorkCheckIn into Note objects.
    @MainActor
    static func migrateWorkCheckInNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<WorkCheckIn>(
            predicate: #Predicate<WorkCheckIn> { wci in
                !wci.note.isEmpty
            }
        )
        let checkIns = context.safeFetch(fetch)

        var migratedCount = 0

        for checkIn in checkIns {
            // Check if notes relationship is empty - skip if already migrated
            guard (checkIn.notes ?? []).isEmpty else { continue }

            // Determine scope from associated work's students if available
            var scope: NoteScope = .all
            if let work = checkIn.work {
                // Get student IDs from participants or fall back to singular studentID
                var studentUUIDs: [UUID] = []
                if let participants = work.participants, !participants.isEmpty {
                    studentUUIDs = participants.compactMap { UUID(uuidString: $0.studentID) }
                } else if let studentUUID = UUID(uuidString: work.studentID) {
                    studentUUIDs = [studentUUID]
                }

                if studentUUIDs.count == 1 {
                    scope = .student(studentUUIDs[0])
                } else if studentUUIDs.count > 1 {
                    scope = .students(studentUUIDs)
                }
            }

            let note = Note(
                createdAt: checkIn.date,
                body: checkIn.note,
                scope: scope,
                category: .general,
                workCheckIn: checkIn
            )

            context.insert(note)
            checkIn.note = ""
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - WorkCompletionRecord Notes

    /// Migrate legacy string notes on WorkCompletionRecord into Note objects.
    @MainActor
    static func migrateWorkCompletionRecordNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<WorkCompletionRecord>(
            predicate: #Predicate<WorkCompletionRecord> { wcr in
                !wcr.note.isEmpty
            }
        )
        let records = context.safeFetch(fetch)

        var migratedCount = 0

        for record in records {
            // Check if notes relationship is empty - skip if already migrated
            guard (record.notes ?? []).isEmpty else { continue }

            // Scope to the specific student
            let scope: NoteScope
            if let studentUUID = UUID(uuidString: record.studentID) {
                scope = .student(studentUUID)
            } else {
                scope = .all
            }

            let note = Note(
                createdAt: record.completedAt,
                body: record.note,
                scope: scope,
                category: .general,
                workCompletionRecord: record
            )

            context.insert(note)
            record.note = ""
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - AttendanceRecord Notes

    /// Migrate legacy string notes on AttendanceRecord into Note objects.
    @MainActor
    static func migrateAttendanceNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<AttendanceRecord>()
        let records = context.safeFetch(fetch)

        var migratedCount = 0

        for record in records {
            // Check if note has content
            guard let legacyNote = record.note, !legacyNote.isEmpty else { continue }
            // Check if notes relationship is empty - skip if already migrated
            guard (record.notes ?? []).isEmpty else { continue }

            // Scope to the specific student
            let scope: NoteScope
            if let studentUUID = UUID(uuidString: record.studentID) {
                scope = .student(studentUUID)
            } else {
                scope = .all
            }

            let note = Note(
                createdAt: record.date,
                body: legacyNote,
                scope: scope,
                category: .attendance,
                attendanceRecord: record
            )

            context.insert(note)
            record.note = nil
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - ProjectSession Notes

    /// Migrate legacy string notes on ProjectSession into Note objects.
    @MainActor
    static func migrateProjectSessionNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<ProjectSession>()
        let sessions = context.safeFetch(fetch)

        var migratedCount = 0

        for session in sessions {
            // Check if notes has content
            guard let legacyNotes = session.notes, !legacyNotes.isEmpty else { continue }
            // Check if noteItems relationship is empty - skip if already migrated
            guard (session.noteItems ?? []).isEmpty else { continue }

            let note = Note(
                createdAt: session.meetingDate,
                body: legacyNotes,
                scope: .all,
                category: .general,
                projectSession: session
            )

            context.insert(note)
            session.notes = nil
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - StudentTrackEnrollment Notes

    /// Migrate legacy string notes on StudentTrackEnrollment into Note objects.
    @MainActor
    static func migrateStudentTrackEnrollmentNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<StudentTrackEnrollment>()
        let enrollments = context.safeFetch(fetch)

        var migratedCount = 0

        for enrollment in enrollments {
            // Check if notes has content
            guard let legacyNotes = enrollment.notes, !legacyNotes.isEmpty else { continue }
            // Check if richNotes relationship is empty - skip if already migrated
            guard (enrollment.richNotes ?? []).isEmpty else { continue }

            // Scope to the specific student
            let scope: NoteScope
            if let studentUUID = UUID(uuidString: enrollment.studentID) {
                scope = .student(studentUUID)
            } else {
                scope = .all
            }

            let note = Note(
                createdAt: enrollment.createdAt,
                body: legacyNotes,
                scope: scope,
                category: .general,
                studentTrackEnrollment: enrollment
            )

            context.insert(note)
            enrollment.notes = nil
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - SchoolDayOverride Notes

    /// Migrate legacy string notes on SchoolDayOverride into Note objects.
    @MainActor
    static func migrateSchoolDayOverrideNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<SchoolDayOverride>()
        let overrides = context.safeFetch(fetch)

        var migratedCount = 0

        for override in overrides {
            // Check if note has content
            guard let legacyNote = override.note, !legacyNote.isEmpty else { continue }
            // Check if notes relationship is empty - skip if already migrated
            guard (override.notes ?? []).isEmpty else { continue }

            let note = Note(
                createdAt: override.date,
                body: legacyNote,
                scope: .all,
                category: .general,
                schoolDayOverride: override
            )

            context.insert(note)
            override.note = nil
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - Reminder Notes

    /// Migrate legacy string notes on Reminder into Note objects.
    /// Note: Reminders sync with EventKit, so notes field may be populated from external source.
    /// This migration preserves the sync behavior by not clearing notes field for EventKit-synced reminders.
    @MainActor
    static func migrateReminderNotes(using context: ModelContext) {
        let fetch = FetchDescriptor<Reminder>()
        let reminders = context.safeFetch(fetch)

        var migratedCount = 0

        for reminder in reminders {
            // Check if notes has content
            guard let legacyNotes = reminder.notes, !legacyNotes.isEmpty else { continue }
            // Check if noteItems relationship is empty - skip if already migrated
            guard (reminder.noteItems ?? []).isEmpty else { continue }
            // Skip EventKit-synced reminders to preserve external sync behavior
            guard reminder.eventKitReminderID == nil else { continue }

            let note = Note(
                createdAt: reminder.createdAt,
                body: legacyNotes,
                scope: .all,
                category: .general,
                reminder: reminder
            )

            context.insert(note)
            reminder.notes = nil
            migratedCount += 1
        }

        if migratedCount > 0 {
            context.safeSave()
        }
    }

    // MARK: - Run All Legacy Notes Migrations

    /// Runs all legacy notes migrations in sequence.
    /// Safe to call repeatedly - each migration is idempotent.
    @MainActor
    static func runAllLegacyNotesMigrations(using context: ModelContext) {
        migrateStudentLessonNotes(using: context)
        migrateWorkNotes(using: context)
        migrateWorkCheckInNotes(using: context)
        migrateWorkCompletionRecordNotes(using: context)
        migrateAttendanceNotes(using: context)
        migrateProjectSessionNotes(using: context)
        migrateStudentTrackEnrollmentNotes(using: context)
        migrateSchoolDayOverrideNotes(using: context)
        migrateReminderNotes(using: context)
    }
}
