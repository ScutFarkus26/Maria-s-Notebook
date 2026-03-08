// SelectiveExportService.swift
// Handles selective/filtered backup exports
// swiftlint:disable file_length

import Foundation
import SwiftData
import OSLog

/// Service for creating selective backups with filtered entities
@MainActor
// swiftlint:disable:next type_body_length
public final class SelectiveExportService {
    private static let logger = Logger.backup

    // MARK: - Types

    /// Options for filtering what to include in a backup
    public struct ExportFilter: Sendable {
        /// Specific student IDs to include (nil = all students)
        public var studentIDs: Set<UUID>?

        /// Date range for entities (nil = no date filter)
        public var dateRange: ClosedRange<Date>?

        /// Specific entity types to include (nil = all types)
        public var entityTypes: Set<EntityType>?

        /// Specific project IDs to include (nil = all projects)
        public var projectIDs: Set<UUID>?

        /// Whether to include related entities automatically
        public var includeRelatedEntities: Bool

        public init(
            studentIDs: Set<UUID>? = nil,
            dateRange: ClosedRange<Date>? = nil,
            entityTypes: Set<EntityType>? = nil,
            projectIDs: Set<UUID>? = nil,
            includeRelatedEntities: Bool = true
        ) {
            self.studentIDs = studentIDs
            self.dateRange = dateRange
            self.entityTypes = entityTypes
            self.projectIDs = projectIDs
            self.includeRelatedEntities = includeRelatedEntities
        }

        public static var all: ExportFilter {
            ExportFilter()
        }
    }

    /// Entity types that can be selectively exported
    public enum EntityType: String, CaseIterable, Identifiable, Sendable {
        case students = "Students"
        case lessons = "Lessons"
        case presentations = "Presentations"
        case notes = "Notes"
        case calendar = "Calendar"
        case attendance = "Attendance"
        case workCompletions = "Work Completions"
        case community = "Community"
        case projects = "Projects"
        case preferences = "Preferences"

        public var id: String { rawValue }

        public var description: String {
            switch self {
            case .students: return "Student records and profiles"
            case .lessons: return "Lesson definitions and materials"
            case .presentations: return "Lesson presentation records"
            case .notes: return "Notes attached to various entities"
            case .calendar: return "Non-school days and overrides"
            case .attendance: return "Attendance records"
            case .workCompletions: return "Work completion records"
            case .community: return "Community topics and solutions"
            case .projects: return "Projects with sessions and roles"
            case .preferences: return "App preferences and settings"
            }
        }
    }

    /// Statistics about a selective export
    public struct ExportStatistics: Sendable {
        public let filter: ExportFilter
        public let includedCounts: [String: Int]
        public let excludedCounts: [String: Int]
        public let estimatedSize: Int64
        public let relatedEntitiesAdded: Int
    }

    // MARK: - Properties

    private let backupService: BackupService
    private let codec = BackupCodec()
    
    // MARK: - Helper
    
    private func safeFetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext,
        functionName: String = #function
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.warning("[\(functionName)] Failed to fetch \(T.self): \(error)")
            return []
        }
    }
    
    // MARK: - Initialization
    
    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    // MARK: - Public API

    // swiftlint:disable function_body_length
    /// Creates a selective backup with the given filter
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - url: Destination URL for the backup file
    ///   - filter: Filter options for what to include
    ///   - password: Optional encryption password
    ///   - progress: Progress callback
    /// - Returns: Summary of the export operation
    public func exportSelective(
        modelContext: ModelContext,
        to url: URL,
        filter: ExportFilter,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        progress(0.0, "Preparing selective export…")

        // Collect filtered entities
        let (payload, counts) = try collectFilteredPayload(
            modelContext: modelContext,
            filter: filter,
            progress: { subProgress, message in
                progress(subProgress * 0.4, message)
            }
        )

        progress(0.4, "Encoding \(counts.values.reduce(0, +)) entities…")

        // Encode payload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(0.5, "Compressing data…")
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        // Encrypt if password provided
        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(0.6, "Encrypting data…")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalCompressed = compressedPayloadBytes
        }

        // Build envelope
        let envelope = BackupServiceHelpers.buildEnvelope(
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: counts,
            sha256: sha,
            notes: "Selective export"
        )

        progress(0.8, "Writing backup file…")
        try BackupServiceHelpers.writeBackupFile(envelope: envelope, to: url, encoder: encoder)

        progress(1.0, "Selective export complete")

        var warnings: [String] = []
        if filter.studentIDs != nil {
            warnings.append("This backup only includes selected students.")
        }
        if filter.dateRange != nil {
            warnings.append("This backup only includes data within the specified date range.")
        }
        if filter.entityTypes != nil {
            warnings.append("This backup only includes selected entity types.")
        }

        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: finalEncrypted != nil,
            createdAt: Date(),
            entityCounts: counts,
            warnings: warnings
        )
    }
    // swiftlint:enable function_body_length

    // swiftlint:disable function_body_length
    /// Previews what would be included in a selective export
    public func previewSelectiveExport(
        modelContext: ModelContext,
        filter: ExportFilter
    ) -> ExportStatistics {
        var includedCounts: [String: Int] = [:]
        var excludedCounts: [String: Int] = [:]
        let relatedEntitiesAdded = 0

        // Count all entities
        let allStudents = safeFetch(FetchDescriptor<Student>(), context: modelContext)
        let allLessons = safeFetch(FetchDescriptor<Lesson>(), context: modelContext)
        let allNotes = safeFetch(FetchDescriptor<Note>(), context: modelContext)
        let allProjects = safeFetch(FetchDescriptor<Project>(), context: modelContext)

        // Apply student filter
        let includedStudents: [Student]
        if let studentIDs = filter.studentIDs {
            includedStudents = allStudents.filter { studentIDs.contains($0.id) }
        } else {
            includedStudents = allStudents
        }
        includedCounts["Student"] = includedStudents.count
        excludedCounts["Student"] = allStudents.count - includedStudents.count

        // Filter lessons (include all if related entities enabled, or specific filter)
        let includedLessons: [Lesson]
        if filter.entityTypes?.contains(.lessons) ?? true {
            includedLessons = allLessons
        } else {
            includedLessons = []
        }
        includedCounts["Lesson"] = includedLessons.count
        excludedCounts["Lesson"] = allLessons.count - includedLessons.count

        // Filter notes
        let includedNotes: [Note]
        if filter.entityTypes?.contains(.notes) ?? true {
            if let dateRange = filter.dateRange {
                includedNotes = allNotes.filter { dateRange.contains($0.createdAt) }
            } else {
                includedNotes = allNotes
            }
        } else {
            includedNotes = []
        }
        includedCounts["Note"] = includedNotes.count
        excludedCounts["Note"] = allNotes.count - includedNotes.count

        // Filter projects
        let includedProjects: [Project]
        if let projectIDs = filter.projectIDs {
            includedProjects = allProjects.filter { projectIDs.contains($0.id) }
        } else if filter.entityTypes?.contains(.projects) ?? true {
            includedProjects = allProjects
        } else {
            includedProjects = []
        }
        includedCounts["Project"] = includedProjects.count
        excludedCounts["Project"] = allProjects.count - includedProjects.count

        // Estimate size
        let estimatedSize = backupService.estimateBackupSizeFromCounts(includedCounts)

        return ExportStatistics(
            filter: filter,
            includedCounts: includedCounts,
            excludedCounts: excludedCounts,
            estimatedSize: estimatedSize,
            relatedEntitiesAdded: relatedEntitiesAdded
        )
    }
    // swiftlint:enable function_body_length

    /// Exports a single project with all related data
    public func exportProject(
        _ projectID: UUID,
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let filter = ExportFilter(
            entityTypes: [.projects, .students],
            projectIDs: [projectID],
            includeRelatedEntities: true
        )

        return try await exportSelective(
            modelContext: modelContext,
            to: url,
            filter: filter,
            password: password,
            progress: progress
        )
    }

    /// Exports data for specific students
    public func exportStudents(
        _ studentIDs: Set<UUID>,
        modelContext: ModelContext,
        to url: URL,
        includeHistory: Bool = true,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        var entityTypes: Set<EntityType> = [.students]
        if includeHistory {
            entityTypes.insert(.presentations)
            entityTypes.insert(.attendance)
            entityTypes.insert(.workCompletions)
            entityTypes.insert(.notes)
        }

        let filter = ExportFilter(
            studentIDs: studentIDs,
            entityTypes: entityTypes,
            includeRelatedEntities: true
        )

        return try await exportSelective(
            modelContext: modelContext,
            to: url,
            filter: filter,
            password: password,
            progress: progress
        )
    }

    // MARK: - Private Helpers

    private func collectFilteredPayload(
        modelContext: ModelContext,
        filter: ExportFilter,
        progress: @escaping BackupService.ProgressCallback
    ) throws -> (BackupPayload, [String: Int]) {
        var counts: [String: Int] = [:]

        func shouldInclude(_ type: EntityType) -> Bool {
            filter.entityTypes?.contains(type) ?? true
        }

        var payload = BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [],
            notes: [], nonSchoolDays: [], schoolDayOverrides: [],
            studentMeetings: [], communityTopics: [],
            proposedSolutions: [], communityAttachments: [],
            attendance: [], workCompletions: [],
            projects: [], projectAssignmentTemplates: [],
            projectSessions: [], projectRoles: [],
            projectTemplateWeeks: [], projectWeekRoleAssignments: [],
            preferences: PreferencesDTO(values: [:])
        )

        collectCoreFilteredDTOs(
            into: &payload, counts: &counts, modelContext: modelContext,
            filter: filter, shouldInclude: shouldInclude, progress: progress
        )
        collectProjectFilteredDTOs(
            into: &payload, counts: &counts, modelContext: modelContext,
            filter: filter, shouldInclude: shouldInclude, progress: progress
        )

        progress(0.9, "Collecting preferences…")
        if shouldInclude(.preferences) {
            payload.preferences = BackupPreferencesService.buildPreferencesDTO()
        }

        return (payload, counts)
    }

    // swiftlint:disable:next function_parameter_count
    private func collectCoreFilteredDTOs(
        into payload: inout BackupPayload,
        counts: inout [String: Int],
        modelContext: ModelContext,
        filter: ExportFilter,
        shouldInclude: (EntityType) -> Bool,
        progress: @escaping BackupService.ProgressCallback
    ) {
        progress(0.1, "Collecting students…")
        payload.students = shouldInclude(.students)
            ? collectStudents(modelContext: modelContext, filter: filter) : []
        counts["Student"] = payload.students.count

        progress(0.2, "Collecting lessons…")
        payload.lessons = shouldInclude(.lessons)
            ? collectLessons(modelContext: modelContext) : []
        counts["Lesson"] = payload.lessons.count

        progress(0.5, "Collecting other entities…")
        payload.notes = shouldInclude(.notes)
            ? collectNotes(modelContext: modelContext, filter: filter) : []
        counts["Note"] = payload.notes.count

        payload.nonSchoolDays = shouldInclude(.calendar)
            ? collectNonSchoolDays(modelContext: modelContext, filter: filter) : []
        counts["NonSchoolDay"] = payload.nonSchoolDays.count

        payload.schoolDayOverrides = shouldInclude(.calendar)
            ? collectSchoolDayOverrides(modelContext: modelContext, filter: filter) : []
        counts["SchoolDayOverride"] = payload.schoolDayOverrides.count

        payload.attendance = shouldInclude(.attendance)
            ? collectAttendance(modelContext: modelContext, filter: filter) : []
        counts["AttendanceRecord"] = payload.attendance.count

        payload.workCompletions = shouldInclude(.workCompletions)
            ? collectWorkCompletions(modelContext: modelContext, filter: filter) : []
        counts["WorkCompletionRecord"] = payload.workCompletions.count
    }

    // swiftlint:disable:next function_parameter_count
    private func collectProjectFilteredDTOs(
        into payload: inout BackupPayload,
        counts: inout [String: Int],
        modelContext: ModelContext,
        filter: ExportFilter,
        shouldInclude: (EntityType) -> Bool,
        progress: @escaping BackupService.ProgressCallback
    ) {
        progress(0.7, "Collecting projects…")
        payload.projects = shouldInclude(.projects)
            ? collectProjects(modelContext: modelContext, filter: filter) : []
        counts["Project"] = payload.projects.count

        payload.projectAssignmentTemplates = shouldInclude(.projects)
            ? collectProjectTemplates(modelContext: modelContext, filter: filter) : []
        counts["ProjectAssignmentTemplate"] = payload.projectAssignmentTemplates.count

        payload.projectSessions = shouldInclude(.projects)
            ? collectProjectSessions(modelContext: modelContext, filter: filter) : []
        counts["ProjectSession"] = payload.projectSessions.count

        payload.projectRoles = shouldInclude(.projects)
            ? collectProjectRoles(modelContext: modelContext, filter: filter) : []
        counts["ProjectRole"] = payload.projectRoles.count

        payload.projectTemplateWeeks = shouldInclude(.projects)
            ? collectProjectWeeks(modelContext: modelContext, filter: filter) : []
        counts["ProjectTemplateWeek"] = payload.projectTemplateWeeks.count

        payload.projectWeekRoleAssignments = shouldInclude(.projects)
            ? collectProjectWeekAssignments(modelContext: modelContext, filter: filter) : []
        counts["ProjectWeekRoleAssignment"] = payload.projectWeekRoleAssignments.count
    }

    private func collectStudents(modelContext: ModelContext, filter: ExportFilter) -> [StudentDTO] {
        let allStudents = safeFetch(FetchDescriptor<Student>(), context: modelContext)
        let filtered = filter.studentIDs.map { ids in allStudents.filter { ids.contains($0.id) } } ?? allStudents
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectLessons(modelContext: ModelContext) -> [LessonDTO] {
        let allLessons = safeFetch(FetchDescriptor<Lesson>(), context: modelContext)
        return BackupServiceHelpers.toDTOs(allLessons)
    }

}

// MARK: - Collection Helpers

extension SelectiveExportService {
    private func collectNotes(modelContext: ModelContext, filter: ExportFilter) -> [NoteDTO] {
        let all = safeFetch(FetchDescriptor<Note>(), context: modelContext)
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.createdAt }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    // Removed: collectPresentations - Presentations are no longer exported; LessonAssignment is used instead

    private func collectNonSchoolDays(modelContext: ModelContext, filter: ExportFilter) -> [NonSchoolDayDTO] {
        let all = safeFetch(FetchDescriptor<NonSchoolDay>(), context: modelContext)
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectSchoolDayOverrides(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [SchoolDayOverrideDTO] {
        let all = safeFetch(FetchDescriptor<SchoolDayOverride>(), context: modelContext)
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectAttendance(modelContext: ModelContext, filter: ExportFilter) -> [AttendanceRecordDTO] {
        let all = safeFetch(FetchDescriptor<AttendanceRecord>(), context: modelContext)
        var filtered = BackupServiceHelpers.filterByStudents(
            all, studentIDs: filter.studentIDs
        ) { UUID(uuidString: $0.studentID) }
        filtered = BackupServiceHelpers.filterByDateRange(filtered, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectWorkCompletions(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [WorkCompletionRecordDTO] {
        let all = safeFetch(FetchDescriptor<WorkCompletionRecord>(), context: modelContext)
        var filtered = BackupServiceHelpers.filterByStudents(
            all, studentIDs: filter.studentIDs
        ) { UUID(uuidString: $0.studentID) }
        filtered = BackupServiceHelpers.filterByDateRange(
            filtered, dateRange: filter.dateRange
        ) { $0.completedAt }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjects(modelContext: ModelContext, filter: ExportFilter) -> [ProjectDTO] {
        let all = safeFetch(FetchDescriptor<Project>(), context: modelContext)
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { $0.id }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectTemplates(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [ProjectAssignmentTemplateDTO] {
        let all = safeFetch(
            FetchDescriptor<ProjectAssignmentTemplate>(),
            context: modelContext
        )
        let filtered = BackupServiceHelpers.filterByProjects(
            all, projectIDs: filter.projectIDs
        ) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectSessions(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [ProjectSessionDTO] {
        let all = safeFetch(
            FetchDescriptor<ProjectSession>(), context: modelContext
        )
        let filtered = BackupServiceHelpers.filterByProjects(
            all, projectIDs: filter.projectIDs
        ) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectRoles(modelContext: ModelContext, filter: ExportFilter) -> [ProjectRoleDTO] {
        let all = safeFetch(FetchDescriptor<ProjectRole>(), context: modelContext)
        let filtered = BackupServiceHelpers.filterByProjects(
            all, projectIDs: filter.projectIDs
        ) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectWeeks(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [ProjectTemplateWeekDTO] {
        let all = safeFetch(
            FetchDescriptor<ProjectTemplateWeek>(),
            context: modelContext
        )
        let filtered = BackupServiceHelpers.filterByProjects(
            all, projectIDs: filter.projectIDs
        ) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectWeekAssignments(
        modelContext: ModelContext, filter: ExportFilter
    ) -> [ProjectWeekRoleAssignmentDTO] {
        let all = safeFetch(FetchDescriptor<ProjectWeekRoleAssignment>(), context: modelContext)

        if let projectIDs = filter.projectIDs {
            let weeks = safeFetch(FetchDescriptor<ProjectTemplateWeek>(), context: modelContext)
            let includedWeekIDs = Set(weeks.filter { w in
                guard let pid = UUID(uuidString: w.projectID) else { return false }
                return projectIDs.contains(pid)
            }.map { $0.id.uuidString })
            let filtered = all.filter { includedWeekIDs.contains($0.weekID) }
            return BackupServiceHelpers.toDTOs(filtered)
        }

        return BackupServiceHelpers.toDTOs(all)
    }
}
