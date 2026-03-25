// SelectiveRestoreService.swift
// Enables selective restoration of specific entity types from backups

import Foundation
import SwiftData

/// Service for selectively restoring specific entity types from a backup.
/// Allows users to restore only Students, or only Lessons, etc.
@MainActor
public final class SelectiveRestoreService {

    // MARK: - Properties

    private let backupService: BackupService
    let codec = BackupCodec()

    // MARK: - Entity Lookup Caches

    /// Lookup dictionaries for entities that need to be linked during import.
    /// These provide O(1) access by ID instead of repeated database queries.
    var studentsByID: [UUID: Student] = [:]
    var lessonsByID: [UUID: Lesson] = [:]
    var topicsByID: [UUID: CommunityTopic] = [:]
    var templateWeeksByID: [UUID: ProjectTemplateWeek] = [:]

    /// ID sets for simple existence checks (no entity retrieval needed)
    var existingIDSets: [String: Set<UUID>] = [:]

    // MARK: - Initialization

    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    // MARK: - Public API

    /// Analyzes a backup file to show what entities are available for selective restore.
    ///
    /// - Parameters:
    ///   - url: The backup file URL
    ///   - password: Optional decryption password
    ///   - progress: Progress callback
    /// - Returns: Dictionary mapping entity types to their counts in the backup
    public func analyzeBackup(
        from url: URL,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> [RestorableEntityType: Int] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.1, "Reading backup file…")
        let payload = try await extractPayload(from: url, password: password)

        progress(0.9, "Analyzing contents…")
        var counts: [RestorableEntityType: Int] = [:]

        counts[.students] = payload.students.count
        counts[.lessons] = payload.lessons.count
        counts[.notes] = payload.notes.count
        counts[.calendar] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
        counts[.meetings] = payload.studentMeetings.count
        counts[.community] = payload.communityTopics.count
            + payload.proposedSolutions.count
            + payload.communityAttachments.count
        counts[.attendance] = payload.attendance.count
        counts[.workCompletions] = payload.workCompletions.count
        counts[.projects] = payload.projects.count + payload.projectAssignmentTemplates.count +
            payload.projectSessions.count + payload.projectRoles.count +
            payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count

        progress(1.0, "Analysis complete")
        return counts
    }

    // Previews a selective restore operation.
    //
    // - Parameters:
    //   - url: The backup file URL
    //   - options: Selective restore options
    //   - modelContext: The model context
    //   - password: Optional decryption password
    //   - progress: Progress callback
    // - Returns: Preview of what would be restored
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func previewSelectiveRestore(
        from url: URL,
        options: SelectiveRestoreOptions,
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> SelectiveRestorePreview {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.1, "Reading backup file…")
        let payload = try await extractPayload(from: url, password: password)

        progress(0.5, "Analyzing selections…")
        let resolved = options.resolvedEntityTypes
        var counts: [RestorableEntityType: Int] = [:]
        var warnings: [String] = []
        var missing: [RestorableEntityType] = []

        // Check for missing dependencies
        for type in options.entityTypes {
            for dep in type.dependencies {
                if !options.entityTypes.contains(dep) && !options.includeDependencies {
                    missing.append(dep)
                }
            }
        }

        if !missing.isEmpty {
            let names = missing.map(\.rawValue).joined(separator: ", ")
            warnings.append(
                "Some entities have dependencies that are not selected: \(names)"
            )
        }

        // Count entities for each selected type
        for type in resolved {
            switch type {
            case .students:
                counts[type] = payload.students.count
            case .lessons:
                counts[type] = payload.lessons.count
            case .notes:
                counts[type] = payload.notes.count
            case .calendar:
                counts[type] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
            case .meetings:
                counts[type] = payload.studentMeetings.count
            case .community:
                counts[type] = payload.communityTopics.count
                    + payload.proposedSolutions.count
                    + payload.communityAttachments.count
            case .attendance:
                counts[type] = payload.attendance.count
            case .workCompletions:
                counts[type] = payload.workCompletions.count
            case .projects:
                counts[type] = payload.projects.count + payload.projectAssignmentTemplates.count +
                    payload.projectSessions.count + payload.projectRoles.count +
                    payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
            }
        }

        progress(1.0, "Preview complete")
        return SelectiveRestorePreview(
            entityCounts: counts,
            warnings: warnings,
            missingDependencies: missing
        )
    }

    /// Performs a selective restore, importing only the specified entity types.
    ///
    /// - Parameters:
    ///   - url: The backup file URL
    ///   - options: Selective restore options
    ///   - modelContext: The model context to import into
    ///   - password: Optional decryption password
    ///   - progress: Progress callback
    /// - Returns: Result of the selective restore
    public func performSelectiveRestore(
        from url: URL,
        options: SelectiveRestoreOptions,
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> SelectiveRestoreResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading backup file…")
        let payload = try await extractPayload(from: url, password: password)

        progress(0.08, "Building lookup caches…")
        buildExistingIDCaches(in: modelContext)
        defer { clearIDCaches() }

        let resolved = options.resolvedEntityTypes
        var importedCounts: [RestorableEntityType: Int] = [:]
        var skippedCounts: [RestorableEntityType: Int] = [:]
        var warnings: [String] = []

        // Calculate progress steps
        let totalSteps = Double(resolved.count)
        var currentStep = 0.0

        func updateProgress(_ message: String) {
            currentStep += 1
            let p = 0.1 + (currentStep / totalSteps) * 0.85
            progress(p, message)
        }

        // Import entities in dependency order
        let orderedTypes: [RestorableEntityType] = [
            .students, .lessons,
            .notes, .calendar, .meetings,
            .community, .attendance, .workCompletions, .projects
        ]

        for type in orderedTypes where resolved.contains(type) {
            updateProgress("Importing \(type.rawValue)…")

            let result = try await importEntityType(
                type,
                from: payload,
                into: modelContext,
                mode: options.mode
            )

            importedCounts[type] = result.imported
            skippedCounts[type] = result.skipped
            if !result.warning.isEmpty {
                warnings.append(result.warning)
            }
        }

        // Save changes
        progress(0.95, "Saving changes…")
        try modelContext.save()

        progress(1.0, "Selective restore complete")
        return SelectiveRestoreResult(
            importedCounts: importedCounts,
            skippedCounts: skippedCounts,
            warnings: warnings
        )
    }
}
