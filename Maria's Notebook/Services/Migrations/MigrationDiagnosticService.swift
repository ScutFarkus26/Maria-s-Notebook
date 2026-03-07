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

    // Runs a comprehensive diagnostic check and returns a detailed report.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func runDiagnostics() async -> MigrationDiagnosticReport {
        var report = MigrationDiagnosticReport()

        logger.info("Starting migration diagnostics...")

        // 1. Count all records
        let lessonAssignments = fetchAll(LessonAssignment.self)
        let notes = fetchAll(Note.self)

        report.counts = RecordCounts(
            lessonAssignments: lessonAssignments.count,
            notes: notes.count
        )

        // 2. Check for LessonAssignment records with missing data
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

        // 3. Check for duplicate migrations
        var seenLegacyIDs = Set<String>()
        var seenPresentationIDs = Set<String>()

        for la in lessonAssignments {
            if let slID = la.migratedFromStudentLessonID {
                if seenLegacyIDs.contains(slID) {
                    report.duplicateMigrations.append(DuplicateMigration(
                        sourceType: "LegacyAssignment",
                        sourceID: slID,
                        lessonAssignmentID: la.id
                    ))
                }
                seenLegacyIDs.insert(slID)
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

    /// Attempts to fix common issues (no-op now that legacy model is removed).
    func fixCommonIssues() async -> MigrationFixResult {
        logger.info("Fix common issues: no legacy data to fix")
        return MigrationFixResult()
    }

    // MARK: - Private Helpers

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        do {
            return try context.fetch(FetchDescriptor<T>())
        } catch {
            logger.warning("Failed to fetch \(type, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Report Types

struct MigrationDiagnosticReport {
    var counts = RecordCounts()
    var lessonAssignmentIssues: [LessonAssignmentIssue] = []
    var duplicateMigrations: [DuplicateMigration] = []

    var isClean: Bool {
        lessonAssignmentIssues.isEmpty &&
        duplicateMigrations.isEmpty
    }

    var summary: String {
        if isClean {
            return "All data looks correct (\(counts.lessonAssignments) LessonAssignments)"
        }

        var parts: [String] = []
        if !lessonAssignmentIssues.isEmpty {
            parts.append("\(lessonAssignmentIssues.count) LessonAssignment data issues")
        }
        if !duplicateMigrations.isEmpty {
            parts.append("\(duplicateMigrations.count) duplicate migrations")
        }

        return "Issues found: " + parts.joined(separator: ", ")
    }
}

struct RecordCounts {
    var lessonAssignments = 0
    var notes = 0
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
