//
//  MigrationDiagnosticService.swift
//  Maria's Notebook
//
//  Diagnostic service to check for data integrity issues in LessonAssignment records.
//

import Foundation
import SwiftData
import OSLog

/// Diagnostic service for checking LessonAssignment data integrity
/// and identifying any records that may have issues.
@MainActor
final class MigrationDiagnosticService {
    private let context: ModelContext
    private let logger = Logger.app(category: "MigrationDiagnostics")

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
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let notes = fetchAll(Note.self)

        report.counts = RecordCounts(
            studentLessons: studentLessons.count,
            lessonAssignments: lessonAssignments.count,
            notes: notes.count
        )

        // 2. Build lookup tables
        let laByStudentLessonID = buildLookup(lessonAssignments, keyPath: \.migratedFromStudentLessonID)

        // 3. Check for unmigrated StudentLessons
        for sl in studentLessons {
            if sl.studentIDs.isEmpty {
                // Corrupted StudentLesson
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

        // 4. Check for Notes attached to old StudentLesson but not LessonAssignment
        for note in notes {
            if note.studentLesson != nil && note.lessonAssignment == nil {
                report.notesOnlyOnLegacyStudentLesson.append(NoteOnLegacyStudentLesson(
                    noteID: note.id,
                    studentLessonID: note.studentLesson?.id,
                    noteBody: String(note.body.prefix(100)),
                    createdAt: note.createdAt
                ))
            }
        }

        // 5. Check for LessonAssignment records with missing data
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
                report.lessonAssignmentIssues.append(LessonAssignmentIssue(
                    id: la.id,
                    state: la.state.rawValue,
                    issues: issues,
                    migratedFromStudentLessonID: la.migratedFromStudentLessonID,
                    migratedFromPresentationID: la.migratedFromPresentationID
                ))
            }
        }

        // 6. Check for duplicate migrations
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

        logger.info("Diagnostics complete: \(report.summary)")

        return report
    }

    /// Attempts to fix common issues by linking notes to corresponding LessonAssignments.
    func fixCommonIssues() async -> MigrationFixResult {
        var result = MigrationFixResult()

        logger.info("Attempting to fix common issues...")

        let lessonAssignments = fetchAll(LessonAssignment.self)
        let notes = fetchAll(Note.self)
        let laByStudentLessonID = buildLookup(lessonAssignments, keyPath: \.migratedFromStudentLessonID)

        // Link notes from old StudentLesson to corresponding LessonAssignment
        for note in notes {
            if let studentLesson = note.studentLesson, note.lessonAssignment == nil {
                if let la = laByStudentLessonID[studentLesson.id.uuidString] {
                    note.lessonAssignment = la
                    result.notesLinked += 1
                }
            }
        }

        if result.notesLinked > 0 {
            context.safeSave()
        }

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
    var notesOnlyOnLegacyStudentLesson: [NoteOnLegacyStudentLesson] = []
    var lessonAssignmentIssues: [LessonAssignmentIssue] = []
    var duplicateMigrations: [DuplicateMigration] = []
    var corruptedStudentLessons: [CorruptedStudentLesson] = []

    var isClean: Bool {
        unmatchedStudentLessons.isEmpty &&
        notesOnlyOnLegacyStudentLesson.isEmpty &&
        lessonAssignmentIssues.isEmpty &&
        duplicateMigrations.isEmpty &&
        corruptedStudentLessons.isEmpty
    }

    var summary: String {
        if isClean {
            return "✅ All data migrated correctly (\(counts.lessonAssignments) LessonAssignments)"
        }

        var parts: [String] = []
        if !unmatchedStudentLessons.isEmpty {
            parts.append("\(unmatchedStudentLessons.count) unmigrated StudentLessons")
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

        return "⚠️ Issues found: " + parts.joined(separator: ", ")
    }
}

struct RecordCounts {
    var studentLessons = 0
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
}

struct DuplicateMigration {
    let sourceType: String
    let sourceID: String
    let lessonAssignmentID: UUID
}

struct MigrationFixResult {
    var notesLinked = 0

    var summary: String {
        if notesLinked > 0 {
            return "Linked \(notesLinked) notes"
        }
        return "No fixes needed"
    }
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
