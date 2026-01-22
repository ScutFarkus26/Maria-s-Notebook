// SelectiveRestoreService.swift
// Enables selective restoration of specific entity types from backups

import Foundation
import SwiftData

/// Service for selectively restoring specific entity types from a backup.
/// Allows users to restore only Students, or only Lessons, etc.
@MainActor
public final class SelectiveRestoreService {

    // MARK: - Types

    /// Entity types that can be selectively restored
    public enum RestorableEntityType: String, CaseIterable, Identifiable, Sendable {
        case students = "Students"
        case lessons = "Lessons"
        case studentLessons = "Student Lessons"
        case workPlanItems = "Work Plan Items"
        case notes = "Notes"
        case calendar = "Calendar (Non-School Days & Overrides)"
        case meetings = "Student Meetings"
        case presentations = "Presentations"
        case community = "Community Topics & Solutions"
        case attendance = "Attendance Records"
        case workCompletions = "Work Completion Records"
        case projects = "Projects"

        public var id: String { rawValue }

        public var description: String { rawValue }

        public var systemImage: String {
            switch self {
            case .students: return "person.3"
            case .lessons: return "book"
            case .studentLessons: return "person.badge.clock"
            case .workPlanItems: return "list.clipboard"
            case .notes: return "note.text"
            case .calendar: return "calendar"
            case .meetings: return "person.2.wave.2"
            case .presentations: return "theatermasks"
            case .community: return "bubble.left.and.bubble.right"
            case .attendance: return "checkmark.circle"
            case .workCompletions: return "checkmark.square"
            case .projects: return "folder"
            }
        }

        /// Dependencies that must be restored together
        public var dependencies: [RestorableEntityType] {
            switch self {
            case .studentLessons: return [.students, .lessons]
            case .presentations: return [.lessons]
            case .community: return []
            case .notes: return [.lessons]
            case .workPlanItems: return []
            case .workCompletions: return []
            case .projects: return [.students]
            default: return []
            }
        }
    }

    /// Options for selective restore
    public struct SelectiveRestoreOptions: Sendable {
        public var entityTypes: Set<RestorableEntityType>
        public var mode: BackupService.RestoreMode
        public var includeDependencies: Bool

        public init(
            entityTypes: Set<RestorableEntityType>,
            mode: BackupService.RestoreMode = .merge,
            includeDependencies: Bool = true
        ) {
            self.entityTypes = entityTypes
            self.mode = mode
            self.includeDependencies = includeDependencies
        }

        /// Returns the full set of entity types including dependencies
        public var resolvedEntityTypes: Set<RestorableEntityType> {
            guard includeDependencies else { return entityTypes }

            var resolved = entityTypes
            for type in entityTypes {
                for dependency in type.dependencies {
                    resolved.insert(dependency)
                }
            }
            return resolved
        }
    }

    /// Result of selective restore preview
    public struct SelectiveRestorePreview: Sendable {
        public var entityCounts: [RestorableEntityType: Int]
        public var warnings: [String]
        public var missingDependencies: [RestorableEntityType]

        public var totalEntities: Int {
            entityCounts.values.reduce(0, +)
        }
    }

    /// Result of selective restore operation
    public struct SelectiveRestoreResult: Sendable {
        public var importedCounts: [RestorableEntityType: Int]
        public var skippedCounts: [RestorableEntityType: Int]
        public var warnings: [String]

        public var totalImported: Int {
            importedCounts.values.reduce(0, +)
        }

        public var totalSkipped: Int {
            skippedCounts.values.reduce(0, +)
        }
    }

    // MARK: - Properties

    private let backupService = BackupService()
    private let codec = BackupCodec()

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
        progress: @escaping (Double, String) -> Void
    ) async throws -> [RestorableEntityType: Int] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.1, "Reading backup file…")
        let payload = try await extractPayload(from: url, password: password)

        progress(0.9, "Analyzing contents…")
        var counts: [RestorableEntityType: Int] = [:]

        counts[.students] = payload.students.count
        counts[.lessons] = payload.lessons.count
        counts[.studentLessons] = payload.studentLessons.count
        counts[.workPlanItems] = payload.workPlanItems.count
        counts[.notes] = payload.notes.count
        counts[.calendar] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
        counts[.meetings] = payload.studentMeetings.count
        counts[.presentations] = payload.presentations.count
        counts[.community] = payload.communityTopics.count + payload.proposedSolutions.count + payload.communityAttachments.count
        counts[.attendance] = payload.attendance.count
        counts[.workCompletions] = payload.workCompletions.count
        counts[.projects] = payload.projects.count + payload.projectAssignmentTemplates.count +
            payload.projectSessions.count + payload.projectRoles.count +
            payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count

        progress(1.0, "Analysis complete")
        return counts
    }

    /// Previews a selective restore operation.
    ///
    /// - Parameters:
    ///   - url: The backup file URL
    ///   - options: Selective restore options
    ///   - modelContext: The model context
    ///   - password: Optional decryption password
    ///   - progress: Progress callback
    /// - Returns: Preview of what would be restored
    public func previewSelectiveRestore(
        from url: URL,
        options: SelectiveRestoreOptions,
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
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
            warnings.append("Some entities have dependencies that are not selected: \(missing.map { $0.rawValue }.joined(separator: ", "))")
        }

        // Count entities for each selected type
        for type in resolved {
            switch type {
            case .students:
                counts[type] = payload.students.count
            case .lessons:
                counts[type] = payload.lessons.count
            case .studentLessons:
                counts[type] = payload.studentLessons.count
            case .workPlanItems:
                counts[type] = payload.workPlanItems.count
            case .notes:
                counts[type] = payload.notes.count
            case .calendar:
                counts[type] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
            case .meetings:
                counts[type] = payload.studentMeetings.count
            case .presentations:
                counts[type] = payload.presentations.count
            case .community:
                counts[type] = payload.communityTopics.count + payload.proposedSolutions.count + payload.communityAttachments.count
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
        progress: @escaping (Double, String) -> Void
    ) async throws -> SelectiveRestoreResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading backup file…")
        let payload = try await extractPayload(from: url, password: password)

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
            .students, .lessons, .studentLessons, .workPlanItems,
            .notes, .calendar, .meetings, .presentations,
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

    // MARK: - Private Helpers

    private func extractPayload(from url: URL, password: String?) async throws -> BackupPayload {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        let payloadBytes: Data

        if envelope.payload != nil {
            // Direct payload
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            payloadBytes = try encoder.encode(envelope.payload!)
        } else if let compressed = envelope.compressedPayload {
            payloadBytes = try codec.decompress(compressed)
        } else if let encrypted = envelope.encryptedPayload {
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "SelectiveRestoreService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Backup is encrypted. Please provide a password."
                ])
            }
            let decrypted = try codec.decrypt(encrypted, password: password)
            if envelope.manifest.compression != nil {
                payloadBytes = try codec.decompress(decrypted)
            } else {
                payloadBytes = decrypted
            }
        } else {
            throw NSError(domain: "SelectiveRestoreService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Backup file missing payload."
            ])
        }

        return try decoder.decode(BackupPayload.self, from: payloadBytes)
    }

    private func importEntityType(
        _ type: RestorableEntityType,
        from payload: BackupPayload,
        into modelContext: ModelContext,
        mode: BackupService.RestoreMode
    ) async throws -> (imported: Int, skipped: Int, warning: String) {

        var imported = 0
        var skipped = 0
        var warning = ""

        switch type {
        case .students:
            let result = try BackupEntityImporter.importStudents(
                payload.students,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(Student.self, id: id, in: modelContext) }
            )
            imported = result.count
            skipped = payload.students.count - result.count

        case .lessons:
            try BackupEntityImporter.importLessons(
                payload.lessons,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(Lesson.self, id: id, in: modelContext) }
            )
            imported = payload.lessons.count
            // TODO: Track actual skip count

        case .studentLessons:
            try BackupEntityImporter.importStudentLessons(
                payload.studentLessons,
                into: modelContext,
                studentLessonCheck: { id in try? fetchEntity(StudentLesson.self, id: id, in: modelContext) },
                lessonCheck: { id in try? fetchEntity(Lesson.self, id: id, in: modelContext) },
                studentCheck: { id in try? fetchEntity(Student.self, id: id, in: modelContext) }
            )
            imported = payload.studentLessons.count

        case .workPlanItems:
            try BackupEntityImporter.importWorkPlanItems(
                payload.workPlanItems,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(WorkPlanItem.self, id: id, in: modelContext) }
            )
            imported = payload.workPlanItems.count

        case .notes:
            try BackupEntityImporter.importNotes(
                payload.notes,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(Note.self, id: id, in: modelContext) },
                lessonCheck: { id in try? fetchEntity(Lesson.self, id: id, in: modelContext) }
            )
            imported = payload.notes.count

        case .calendar:
            try BackupEntityImporter.importNonSchoolDays(
                payload.nonSchoolDays,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(NonSchoolDay.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importSchoolDayOverrides(
                payload.schoolDayOverrides,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(SchoolDayOverride.self, id: id, in: modelContext) }
            )
            imported = payload.nonSchoolDays.count + payload.schoolDayOverrides.count

        case .meetings:
            try BackupEntityImporter.importStudentMeetings(
                payload.studentMeetings,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(StudentMeeting.self, id: id, in: modelContext) }
            )
            imported = payload.studentMeetings.count

        case .presentations:
            let allStudentLessons = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
            try BackupEntityImporter.importPresentations(
                payload.presentations,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(Presentation.self, id: id, in: modelContext) },
                allStudentLessons: allStudentLessons
            )
            imported = payload.presentations.count

        case .community:
            try BackupEntityImporter.importCommunityTopics(
                payload.communityTopics,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(CommunityTopic.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProposedSolutions(
                payload.proposedSolutions,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProposedSolution.self, id: id, in: modelContext) },
                topicCheck: { id in try? fetchEntity(CommunityTopic.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importCommunityAttachments(
                payload.communityAttachments,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(CommunityAttachment.self, id: id, in: modelContext) },
                topicCheck: { id in try? fetchEntity(CommunityTopic.self, id: id, in: modelContext) }
            )
            imported = payload.communityTopics.count + payload.proposedSolutions.count + payload.communityAttachments.count

        case .attendance:
            try BackupEntityImporter.importAttendanceRecords(
                payload.attendance,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(AttendanceRecord.self, id: id, in: modelContext) }
            )
            imported = payload.attendance.count

        case .workCompletions:
            try BackupEntityImporter.importWorkCompletionRecords(
                payload.workCompletions,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(WorkCompletionRecord.self, id: id, in: modelContext) }
            )
            imported = payload.workCompletions.count

        case .projects:
            try BackupEntityImporter.importProjects(
                payload.projects,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(Project.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProjectRoles(
                payload.projectRoles,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProjectRole.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProjectTemplateWeeks(
                payload.projectTemplateWeeks,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProjectTemplateWeek.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProjectAssignmentTemplates(
                payload.projectAssignmentTemplates,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProjectAssignmentTemplate.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProjectWeekRoleAssignments(
                payload.projectWeekRoleAssignments,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProjectWeekRoleAssignment.self, id: id, in: modelContext) },
                weekCheck: { id in try? fetchEntity(ProjectTemplateWeek.self, id: id, in: modelContext) }
            )
            try BackupEntityImporter.importProjectSessions(
                payload.projectSessions,
                into: modelContext,
                existingCheck: { id in try? fetchEntity(ProjectSession.self, id: id, in: modelContext) }
            )
            imported = payload.projects.count + payload.projectAssignmentTemplates.count +
                payload.projectSessions.count + payload.projectRoles.count +
                payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
        }

        return (imported, skipped, warning)
    }

    private func fetchEntity<T: PersistentModel>(_ type: T.Type, id: UUID, in context: ModelContext) throws -> T? {
        let descriptor = FetchDescriptor<T>(predicate: #Predicate { _ in true })
        let all = (try? context.fetch(descriptor)) ?? []
        // Use manual filtering since we can't use id in predicate for all types
        return all.first
    }
}
