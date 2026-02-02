//
//  MigrationDiagnosticService.swift
//  Maria's Notebook
//
//  Diagnostic service to check for unmigrated data and potential data issues
//  during the Presentation -> LessonAssignment migration.
//

import Foundation
import SwiftData
import OSLog

/// Comprehensive diagnostic service for checking migration status
/// and identifying any data that may have been missed.
@MainActor
final class MigrationDiagnosticService {
    private let context: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "MigrationDiagnostics")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Runs a comprehensive diagnostic check and returns a detailed report.
    func runDiagnostics() async -> MigrationDiagnosticReport {
        var report = MigrationDiagnosticReport()

        logger.info("Starting migration diagnostics...")

        // 1. Count all records
        let studentLessons = fetchAll(StudentLesson.self)
        // Presentation model removed - no longer fetching presentations
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let notes = fetchAll(Note.self)

        report.counts = RecordCounts(
            studentLessons: studentLessons.count,
            presentations: 0,  // Presentation model removed
            lessonAssignments: lessonAssignments.count,
            notes: notes.count
        )

        // 2. Build lookup tables
        let laByStudentLessonID = buildLookup(lessonAssignments, keyPath: \.migratedFromStudentLessonID)
        // Presentation model removed - no longer building presentation lookup

        // 3. Check for unmigrated and corrupted StudentLessons
        for sl in studentLessons {
            // Check for corrupted StudentLessons (empty studentIDs)
            if sl.studentIDs.isEmpty {
                var issues: [String] = ["Empty studentIDs"]
                if sl.lessonID.isEmpty {
                    issues.append("Empty lessonID")
                }
                report.corruptedStudentLessons.append(CorruptedStudentLesson(
                    id: sl.id,
                    lessonID: sl.lessonID,
                    lessonName: sl.lesson?.name,
                    isPresented: sl.isPresented,
                    createdAt: sl.createdAt,
                    noteCount: sl.unifiedNotes?.count ?? 0,
                    issues: issues
                ))
            } else if laByStudentLessonID[sl.id.uuidString] == nil {
                // Not corrupted but unmigrated
                report.unmatchedStudentLessons.append(UnmatchedStudentLesson(
                    id: sl.id,
                    lessonID: sl.lessonID,
                    studentIDs: sl.studentIDs,
                    isPresented: sl.isPresented,
                    givenAt: sl.givenAt,
                    scheduledFor: sl.scheduledFor,
                    createdAt: sl.createdAt
                ))
            }
        }

        // Presentation model removed - no longer checking for unmigrated/corrupted Presentations

        // 5. Check for Notes attached to old models but not Presentation
        // Note: Note.presentation relationship is now the unified model.
        for note in notes {
            if note.studentLesson != nil && note.lessonAssignment == nil {
                // Note is attached to old StudentLesson but not to Presentation
                report.notesOnlyOnLegacyStudentLesson.append(NoteOnLegacyStudentLesson(
                    noteID: note.id,
                    studentLessonID: note.studentLesson?.id,
                    noteBody: String(note.body.prefix(100)),
                    createdAt: note.createdAt
                ))
            }
        }

        // Build source lookups for issue diagnostics
        var slByID: [String: StudentLesson] = [:]
        for sl in studentLessons {
            slByID[sl.id.uuidString] = sl
        }

        // Presentation model removed - no longer building presentation lookup

        // 6. Check for LessonAssignment records with missing data
        for la in lessonAssignments {
            var issues: [String] = []

            if la.lessonID.isEmpty {
                issues.append("Empty lessonID")
            }
            if la.studentIDs.isEmpty {
                issues.append("Empty studentIDs")
            }
            if la.state == .presented && la.presentedAt == nil {
                issues.append("Presented state but presentedAt is nil")
            }
            if la.state == .scheduled && la.scheduledFor == nil {
                issues.append("Scheduled state but scheduledFor is nil")
            }

            if !issues.isEmpty {
                // Check if source records have studentIDs
                // Presentation model removed - only checking StudentLesson source
                var sourceHadStudentIDs: Bool? = nil
                if let slID = la.migratedFromStudentLessonID, let sl = slByID[slID] {
                    sourceHadStudentIDs = !sl.studentIDs.isEmpty
                }

                report.lessonAssignmentIssues.append(LessonAssignmentIssue(
                    id: la.id,
                    state: la.state.rawValue,
                    issues: issues,
                    migratedFromStudentLessonID: la.migratedFromStudentLessonID,
                    migratedFromPresentationID: la.migratedFromPresentationID,
                    sourceHadStudentIDs: sourceHadStudentIDs
                ))
            }
        }

        // 7. Check for duplicate migrations (same source migrated multiple times)
        var seenStudentLessonIDs = Set<String>()
        var seenPresentationIDs = Set<String>()

        for la in lessonAssignments {
            if let slID = la.migratedFromStudentLessonID {
                if seenStudentLessonIDs.contains(slID) {
                    report.duplicateMigrations.append(DuplicateMigration(
                        sourceType: "StudentLesson",
                        sourceID: slID,
                        lessonAssignmentID: la.id
                    ))
                }
                seenStudentLessonIDs.insert(slID)
            }
            if let pID = la.migratedFromPresentationID {
                if seenPresentationIDs.contains(pID) {
                    report.duplicateMigrations.append(DuplicateMigration(
                        sourceType: "Presentation",
                        sourceID: pID,
                        lessonAssignmentID: la.id
                    ))
                }
                seenPresentationIDs.insert(pID)
            }
        }

        // Log summary
        logger.info("Diagnostics complete: \(report.summary)")

        return report
    }

    /// Checks orphaned records for attached notes without deleting.
    /// Returns details about each orphaned record and its notes.
    func checkOrphanedRecordsForNotes() -> [OrphanedRecordInfo] {
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let studentLessons = fetchAll(StudentLesson.self)
        // Presentation model removed

        // Build lookup tables
        var slByID: [String: StudentLesson] = [:]
        for sl in studentLessons {
            slByID[sl.id.uuidString] = sl
        }

        // Presentation model removed - no longer building presentation lookup

        var orphanedRecords: [OrphanedRecordInfo] = []

        for la in lessonAssignments {
            guard la.studentIDs.isEmpty else { continue }

            // Check if we can recover from source
            // Presentation model removed - only checking StudentLesson source
            var canRecover = false

            if let slID = la.migratedFromStudentLessonID, let sl = slByID[slID] {
                canRecover = !sl.studentIDs.isEmpty
            }

            // If can't recover, this is an orphaned record
            if !canRecover {
                let noteCount = la.unifiedNotes?.count ?? 0
                let notePreviews = (la.unifiedNotes ?? []).prefix(3).map { String($0.body.prefix(50)) }

                orphanedRecords.append(OrphanedRecordInfo(
                    id: la.id,
                    state: la.state.rawValue,
                    lessonTitle: la.lessonTitleSnapshot ?? la.lesson?.name ?? "Unknown",
                    noteCount: noteCount,
                    notePreviews: notePreviews,
                    migratedFromStudentLessonID: la.migratedFromStudentLessonID,
                    migratedFromPresentationID: la.migratedFromPresentationID
                ))
            }
        }

        return orphanedRecords
    }

    /// Deletes corrupted StudentLesson records that have empty studentIDs.
    /// Returns details about what was deleted.
    /// Note: Presentation model removed - only cleaning up StudentLessons now.
    func deleteCorruptedSourceRecords() -> CorruptedSourceCleanupResult {
        var result = CorruptedSourceCleanupResult()

        let studentLessons = fetchAll(StudentLesson.self)
        // Presentation model removed

        // Delete corrupted StudentLessons
        for sl in studentLessons {
            if sl.studentIDs.isEmpty {
                let noteCount = sl.unifiedNotes?.count ?? 0
                logger.info("Deleting corrupted StudentLesson \(sl.id) (empty studentIDs, \(noteCount) notes will be orphaned)")
                context.delete(sl)
                result.studentLessonsDeleted += 1
                result.notesOrphaned += noteCount
            }
        }

        // Presentation model removed - no longer deleting corrupted Presentations

        if result.totalDeleted > 0 {
            context.safeSave()
            logger.info("Deleted \(result.studentLessonsDeleted) corrupted StudentLessons")
        }

        return result
    }

    /// Deletes LessonAssignment records that have empty studentIDs and can't be recovered.
    /// These are orphaned records that provide no value.
    /// Returns the count of deleted records.
    /// Note: Presentation model removed - only checking StudentLesson sources now.
    func deleteUnrecoverableRecords() -> Int {
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let studentLessons = fetchAll(StudentLesson.self)
        // Presentation model removed

        // Build lookup tables
        var slByID: [String: StudentLesson] = [:]
        for sl in studentLessons {
            slByID[sl.id.uuidString] = sl
        }

        // Presentation model removed - no longer building presentation lookup

        var deletedCount = 0

        for la in lessonAssignments {
            guard la.studentIDs.isEmpty else { continue }

            // Check if we can recover from source
            // Presentation model removed - only checking StudentLesson source
            var canRecover = false

            if let slID = la.migratedFromStudentLessonID, let sl = slByID[slID] {
                canRecover = !sl.studentIDs.isEmpty
            }

            // If can't recover, delete this orphaned record
            if !canRecover {
                let noteCount = la.unifiedNotes?.count ?? 0
                logger.info("Deleting unrecoverable LessonAssignment \(la.id) (empty studentIDs, source also empty or missing, \(noteCount) notes will be orphaned)")
                context.delete(la)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            context.safeSave()
            logger.info("Deleted \(deletedCount) unrecoverable LessonAssignment records")
        }

        return deletedCount
    }

    /// Attempts to fix common migration issues.
    /// Note: Presentation model removed - only recovering from StudentLesson sources now.
    func fixCommonIssues() async -> MigrationFixResult {
        var result = MigrationFixResult()

        logger.info("Attempting to fix common migration issues...")

        // 1. Re-run migration for any unmigrated records
        let migrationService = LessonAssignmentMigrationService(context: context)
        if let migrationResult = try? await migrationService.migrateAll() {
            result.newlyMigrated = migrationResult.totalMigrated
        }

        // 2. Fix LessonAssignments with empty studentIDs by recovering from source records
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let studentLessons = fetchAll(StudentLesson.self)
        // Presentation model removed

        // Build lookup tables
        var slByID: [String: StudentLesson] = [:]
        for sl in studentLessons {
            slByID[sl.id.uuidString] = sl
        }

        // Presentation model removed - no longer building presentation lookup

        for la in lessonAssignments {
            if la.studentIDs.isEmpty {
                var recovered = false

                // Try to recover from source StudentLesson
                if let slID = la.migratedFromStudentLessonID, let sl = slByID[slID] {
                    let studentUUIDs = sl.studentIDs.compactMap { UUID(uuidString: $0) }
                    if !studentUUIDs.isEmpty {
                        la.studentIDs = studentUUIDs.map { $0.uuidString }
                        la.updateDenormalizedKeys()
                        recovered = true
                        logger.info("Recovered studentIDs for LA \(la.id) from StudentLesson \(slID): \(studentUUIDs.count) students")
                    }
                }

                // Presentation model removed - no longer recovering from Presentation sources

                if recovered {
                    result.studentIDsRecovered += 1
                }
            }
        }

        // 3. Link notes from old StudentLesson to corresponding LessonAssignment
        // Note: Presentation model removed - only linking from StudentLesson now
        let notes = fetchAll(Note.self)
        let laByStudentLessonID = buildLookup(lessonAssignments, keyPath: \.migratedFromStudentLessonID)

        for note in notes {
            var fixed = false

            // Fix notes attached to old StudentLesson
            if let studentLesson = note.studentLesson, note.lessonAssignment == nil {
                if let la = laByStudentLessonID[studentLesson.id.uuidString] {
                    note.lessonAssignment = la
                    fixed = true
                }
            }

            if fixed {
                result.notesLinked += 1
            }
        }

        // Save changes
        context.safeSave()

        logger.info("Fix complete: \(result.summary)")

        return result
    }

    // MARK: - Private Helpers

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func buildLookup<T>(_ items: [T], keyPath: KeyPath<T, String?>) -> [String: T] {
        var lookup: [String: T] = [:]
        for item in items {
            if let key = item[keyPath: keyPath], !key.isEmpty {
                lookup[key] = item
            }
        }
        return lookup
    }
}

// MARK: - Report Types

struct MigrationDiagnosticReport {
    var counts = RecordCounts()
    var unmatchedStudentLessons: [UnmatchedStudentLesson] = []
    var unmatchedPresentations: [UnmatchedPresentation] = []
    var notesOnlyOnLegacyPresentation: [NoteOnLegacyPresentation] = []
    var notesOnlyOnLegacyStudentLesson: [NoteOnLegacyStudentLesson] = []
    var lessonAssignmentIssues: [LessonAssignmentIssue] = []
    var duplicateMigrations: [DuplicateMigration] = []
    var corruptedStudentLessons: [CorruptedStudentLesson] = []
    var corruptedPresentations: [CorruptedPresentation] = []

    var isClean: Bool {
        unmatchedStudentLessons.isEmpty &&
        unmatchedPresentations.isEmpty &&
        notesOnlyOnLegacyPresentation.isEmpty &&
        notesOnlyOnLegacyStudentLesson.isEmpty &&
        lessonAssignmentIssues.isEmpty &&
        duplicateMigrations.isEmpty &&
        corruptedStudentLessons.isEmpty &&
        corruptedPresentations.isEmpty
    }

    var summary: String {
        if isClean {
            return "✅ All data migrated correctly (\(counts.lessonAssignments) LessonAssignments)"
        }

        var parts: [String] = []
        if !unmatchedStudentLessons.isEmpty {
            parts.append("\(unmatchedStudentLessons.count) unmigrated StudentLessons")
        }
        if !unmatchedPresentations.isEmpty {
            parts.append("\(unmatchedPresentations.count) unmigrated Presentations")
        }
        if !notesOnlyOnLegacyPresentation.isEmpty {
            parts.append("\(notesOnlyOnLegacyPresentation.count) notes only on legacy Presentation")
        }
        if !notesOnlyOnLegacyStudentLesson.isEmpty {
            parts.append("\(notesOnlyOnLegacyStudentLesson.count) notes only on legacy StudentLesson")
        }
        if !lessonAssignmentIssues.isEmpty {
            parts.append("\(lessonAssignmentIssues.count) LessonAssignment data issues")
        }
        if !duplicateMigrations.isEmpty {
            parts.append("\(duplicateMigrations.count) duplicate migrations")
        }
        if !corruptedStudentLessons.isEmpty {
            parts.append("\(corruptedStudentLessons.count) corrupted StudentLessons")
        }
        if !corruptedPresentations.isEmpty {
            parts.append("\(corruptedPresentations.count) corrupted Presentations")
        }

        return "⚠️ Issues found: " + parts.joined(separator: ", ")
    }

    func detailedReport() -> String {
        var lines: [String] = []

        lines.append("=== MIGRATION DIAGNOSTIC REPORT ===")
        lines.append("")
        lines.append("Record Counts:")
        lines.append("  StudentLessons: \(counts.studentLessons)")
        lines.append("  Presentations: \(counts.presentations)")
        lines.append("  LessonAssignments: \(counts.lessonAssignments)")
        lines.append("  Notes: \(counts.notes)")
        lines.append("")

        if !unmatchedStudentLessons.isEmpty {
            lines.append("UNMIGRATED STUDENTLESSONS (\(unmatchedStudentLessons.count)):")
            for sl in unmatchedStudentLessons.prefix(10) {
                lines.append("  - ID: \(sl.id), LessonID: \(sl.lessonID.prefix(8))..., Presented: \(sl.isPresented), Created: \(sl.createdAt)")
            }
            if unmatchedStudentLessons.count > 10 {
                lines.append("  ... and \(unmatchedStudentLessons.count - 10) more")
            }
            lines.append("")
        }

        if !unmatchedPresentations.isEmpty {
            lines.append("UNMIGRATED PRESENTATIONS (\(unmatchedPresentations.count)):")
            for p in unmatchedPresentations.prefix(10) {
                lines.append("  - ID: \(p.id), LessonID: \(p.lessonID.prefix(8))..., PresentedAt: \(p.presentedAt)")
            }
            if unmatchedPresentations.count > 10 {
                lines.append("  ... and \(unmatchedPresentations.count - 10) more")
            }
            lines.append("")
        }

        if !notesOnlyOnLegacyPresentation.isEmpty {
            lines.append("NOTES ONLY ON LEGACY PRESENTATION (\(notesOnlyOnLegacyPresentation.count)):")
            for n in notesOnlyOnLegacyPresentation.prefix(10) {
                lines.append("  - NoteID: \(n.noteID), PresentationID: \(n.presentationID?.uuidString.prefix(8) ?? "nil")..., Body: \"\(n.noteBody.prefix(50))...\"")
            }
            if notesOnlyOnLegacyPresentation.count > 10 {
                lines.append("  ... and \(notesOnlyOnLegacyPresentation.count - 10) more")
            }
            lines.append("")
        }

        if !notesOnlyOnLegacyStudentLesson.isEmpty {
            lines.append("NOTES ONLY ON LEGACY STUDENTLESSON (\(notesOnlyOnLegacyStudentLesson.count)):")
            for n in notesOnlyOnLegacyStudentLesson.prefix(10) {
                lines.append("  - NoteID: \(n.noteID), StudentLessonID: \(n.studentLessonID?.uuidString.prefix(8) ?? "nil")..., Body: \"\(n.noteBody.prefix(50))...\"")
            }
            if notesOnlyOnLegacyStudentLesson.count > 10 {
                lines.append("  ... and \(notesOnlyOnLegacyStudentLesson.count - 10) more")
            }
            lines.append("")
        }

        if !lessonAssignmentIssues.isEmpty {
            lines.append("LESSONASSIGNMENT DATA ISSUES (\(lessonAssignmentIssues.count)):")
            for issue in lessonAssignmentIssues.prefix(10) {
                var details = "ID: \(issue.id), State: \(issue.state)"
                if let slID = issue.migratedFromStudentLessonID {
                    details += ", fromSL: \(slID.prefix(8))..."
                }
                if let pID = issue.migratedFromPresentationID {
                    details += ", fromP: \(pID.prefix(8))..."
                }
                if let sourceHad = issue.sourceHadStudentIDs {
                    details += ", sourceHadIDs: \(sourceHad ? "YES" : "NO")"
                } else {
                    details += ", sourceHadIDs: N/A (source not found)"
                }
                lines.append("  - \(details)")
                lines.append("    Issues: \(issue.issues.joined(separator: ", "))")
            }
            if lessonAssignmentIssues.count > 10 {
                lines.append("  ... and \(lessonAssignmentIssues.count - 10) more")
            }
            lines.append("")
        }

        if !duplicateMigrations.isEmpty {
            lines.append("DUPLICATE MIGRATIONS (\(duplicateMigrations.count)):")
            for dup in duplicateMigrations.prefix(10) {
                lines.append("  - \(dup.sourceType) \(dup.sourceID.prefix(8))... -> LA \(dup.lessonAssignmentID)")
            }
            if duplicateMigrations.count > 10 {
                lines.append("  ... and \(duplicateMigrations.count - 10) more")
            }
            lines.append("")
        }

        if !corruptedStudentLessons.isEmpty {
            lines.append("CORRUPTED STUDENTLESSONS (\(corruptedStudentLessons.count)):")
            for sl in corruptedStudentLessons.prefix(10) {
                let lessonName = sl.lessonName ?? "Unknown"
                lines.append("  - ID: \(sl.id.uuidString.prefix(8))..., Lesson: \(lessonName), Presented: \(sl.isPresented), Notes: \(sl.noteCount)")
                lines.append("    Issues: \(sl.issues.joined(separator: ", "))")
            }
            if corruptedStudentLessons.count > 10 {
                lines.append("  ... and \(corruptedStudentLessons.count - 10) more")
            }
            lines.append("")
        }

        if !corruptedPresentations.isEmpty {
            lines.append("CORRUPTED PRESENTATIONS (\(corruptedPresentations.count)):")
            for p in corruptedPresentations.prefix(10) {
                let lessonName = p.lessonTitleSnapshot ?? "Unknown"
                lines.append("  - ID: \(p.id.uuidString.prefix(8))..., Lesson: \(lessonName), PresentedAt: \(p.presentedAt), Notes: \(p.noteCount)")
                lines.append("    Issues: \(p.issues.joined(separator: ", "))")
            }
            if corruptedPresentations.count > 10 {
                lines.append("  ... and \(corruptedPresentations.count - 10) more")
            }
            lines.append("")
        }

        lines.append("=== END REPORT ===")

        return lines.joined(separator: "\n")
    }
}

struct RecordCounts {
    var studentLessons = 0
    var presentations = 0
    var lessonAssignments = 0
    var notes = 0
}

struct UnmatchedStudentLesson {
    let id: UUID
    let lessonID: String
    let studentIDs: [String]
    let isPresented: Bool
    let givenAt: Date?
    let scheduledFor: Date?
    let createdAt: Date
}

struct UnmatchedPresentation {
    let id: UUID
    let lessonID: String
    let studentIDs: [String]
    let legacyStudentLessonID: String?
    let presentedAt: Date
    let trackID: String?
    let createdAt: Date
}

struct NoteOnLegacyPresentation {
    let noteID: UUID
    let presentationID: UUID?
    let noteBody: String
    let createdAt: Date
}

struct NoteOnLegacyStudentLesson {
    let noteID: UUID
    let studentLessonID: UUID?
    let noteBody: String
    let createdAt: Date
}

struct LessonAssignmentIssue {
    let id: UUID
    let state: String
    let issues: [String]
    let migratedFromStudentLessonID: String?
    let migratedFromPresentationID: String?
    let sourceHadStudentIDs: Bool?  // nil if source not found
}

struct DuplicateMigration {
    let sourceType: String
    let sourceID: String
    let lessonAssignmentID: UUID
}

struct MigrationFixResult {
    var newlyMigrated = 0
    var notesLinked = 0
    var studentIDsRecovered = 0

    var summary: String {
        var parts: [String] = []
        if newlyMigrated > 0 {
            parts.append("migrated \(newlyMigrated) records")
        }
        if notesLinked > 0 {
            parts.append("linked \(notesLinked) notes")
        }
        if studentIDsRecovered > 0 {
            parts.append("recovered studentIDs for \(studentIDsRecovered) records")
        }
        return parts.isEmpty ? "No fixes needed" : parts.joined(separator: ", ").capitalized
    }
}

struct OrphanedRecordInfo {
    let id: UUID
    let state: String
    let lessonTitle: String
    let noteCount: Int
    let notePreviews: [String]
    let migratedFromStudentLessonID: String?
    let migratedFromPresentationID: String?

    var hasNotes: Bool { noteCount > 0 }
}

struct CorruptedStudentLesson {
    let id: UUID
    let lessonID: String
    let lessonName: String?
    let isPresented: Bool
    let createdAt: Date
    let noteCount: Int
    let issues: [String]
}

struct CorruptedPresentation {
    let id: UUID
    let lessonID: String
    let lessonTitleSnapshot: String?
    let presentedAt: Date
    let createdAt: Date
    let noteCount: Int
    let issues: [String]
}

struct CorruptedSourceCleanupResult {
    var studentLessonsDeleted = 0
    var presentationsDeleted = 0
    var notesOrphaned = 0

    var totalDeleted: Int { studentLessonsDeleted + presentationsDeleted }

    var summary: String {
        if totalDeleted == 0 {
            return "No corrupted source records found"
        }
        var parts: [String] = []
        if studentLessonsDeleted > 0 {
            parts.append("\(studentLessonsDeleted) StudentLessons")
        }
        if presentationsDeleted > 0 {
            parts.append("\(presentationsDeleted) Presentations")
        }
        let base = "Deleted " + parts.joined(separator: " and ")
        if notesOrphaned > 0 {
            return "\(base) (\(notesOrphaned) notes orphaned)"
        }
        return base
    }
}
