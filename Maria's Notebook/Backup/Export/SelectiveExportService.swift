// SelectiveExportService.swift
// Handles selective/filtered backup exports

import Foundation
import SwiftData

/// Service for creating selective backups with filtered entities
@MainActor
public final class SelectiveExportService {

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
        case studentLessons = "Student Lessons"
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
            case .studentLessons: return "Lesson assignments and scheduling"
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
    
    // MARK: - Initialization
    
    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    // MARK: - Public API

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
        progress: @escaping (Double, String) -> Void
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

    /// Previews what would be included in a selective export
    public func previewSelectiveExport(
        modelContext: ModelContext,
        filter: ExportFilter
    ) -> ExportStatistics {
        var includedCounts: [String: Int] = [:]
        var excludedCounts: [String: Int] = [:]
        var relatedEntitiesAdded = 0

        // Count all entities
        let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
        let allLessons = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        let allStudentLessons = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
        let allNotes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        let allProjects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []

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

        // Filter student lessons
        let includedStudentLessons: [StudentLesson]
        if filter.entityTypes?.contains(.studentLessons) ?? true {
            if let studentIDs = filter.studentIDs {
                includedStudentLessons = allStudentLessons.filter { sl in
                    sl.resolvedStudentIDs.contains { studentIDs.contains($0) }
                }
            } else {
                includedStudentLessons = allStudentLessons
            }
        } else {
            includedStudentLessons = []
        }
        includedCounts["StudentLesson"] = includedStudentLessons.count
        excludedCounts["StudentLesson"] = allStudentLessons.count - includedStudentLessons.count

        // If includeRelatedEntities is true, add lessons referenced by student lessons
        if filter.includeRelatedEntities && !includedStudentLessons.isEmpty {
            let referencedLessonIDs = Set(includedStudentLessons.compactMap { UUID(uuidString: $0.lessonID) })
            let additionalLessons = allLessons.filter { referencedLessonIDs.contains($0.id) && !includedLessons.contains($0) }
            relatedEntitiesAdded += additionalLessons.count
        }

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

    /// Exports a single project with all related data
    public func exportProject(
        _ projectID: UUID,
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
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
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        var entityTypes: Set<EntityType> = [.students]
        if includeHistory {
            entityTypes.insert(.studentLessons)
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
        progress: @escaping (Double, String) -> Void
    ) throws -> (BackupPayload, [String: Int]) {
        var counts: [String: Int] = [:]

        func shouldInclude(_ type: EntityType) -> Bool {
            filter.entityTypes?.contains(type) ?? true
        }

        progress(0.1, "Collecting students…")
        let studentDTOs: [StudentDTO] = shouldInclude(.students) ? collectStudents(modelContext: modelContext, filter: filter) : []
        counts["Student"] = studentDTOs.count

        progress(0.2, "Collecting lessons…")
        let lessonDTOs: [LessonDTO] = shouldInclude(.lessons) ? collectLessons(modelContext: modelContext) : []
        counts["Lesson"] = lessonDTOs.count

        progress(0.3, "Collecting student lessons…")
        let studentLessonDTOs: [StudentLessonDTO] = shouldInclude(.studentLessons) ? collectStudentLessons(modelContext: modelContext, filter: filter) : []
        counts["StudentLesson"] = studentLessonDTOs.count

        progress(0.5, "Collecting other entities…")
        let noteDTOs: [NoteDTO] = shouldInclude(.notes) ? collectNotes(modelContext: modelContext, filter: filter) : []
        counts["Note"] = noteDTOs.count

        let nonSchoolDTOs: [NonSchoolDayDTO] = shouldInclude(.calendar) ? collectNonSchoolDays(modelContext: modelContext, filter: filter) : []
        counts["NonSchoolDay"] = nonSchoolDTOs.count

        let schoolOverrideDTOs: [SchoolDayOverrideDTO] = shouldInclude(.calendar) ? collectSchoolDayOverrides(modelContext: modelContext, filter: filter) : []
        counts["SchoolDayOverride"] = schoolOverrideDTOs.count

        let attendanceDTOs: [AttendanceRecordDTO] = shouldInclude(.attendance) ? collectAttendance(modelContext: modelContext, filter: filter) : []
        counts["AttendanceRecord"] = attendanceDTOs.count

        let workCompletionDTOs: [WorkCompletionRecordDTO] = shouldInclude(.workCompletions) ? collectWorkCompletions(modelContext: modelContext, filter: filter) : []
        counts["WorkCompletionRecord"] = workCompletionDTOs.count

        progress(0.7, "Collecting projects…")
        let projectDTOs: [ProjectDTO] = shouldInclude(.projects) ? collectProjects(modelContext: modelContext, filter: filter) : []
        counts["Project"] = projectDTOs.count

        let projectTemplateDTOs: [ProjectAssignmentTemplateDTO] = shouldInclude(.projects) ? collectProjectTemplates(modelContext: modelContext, filter: filter) : []
        counts["ProjectAssignmentTemplate"] = projectTemplateDTOs.count

        let projectSessionDTOs: [ProjectSessionDTO] = shouldInclude(.projects) ? collectProjectSessions(modelContext: modelContext, filter: filter) : []
        counts["ProjectSession"] = projectSessionDTOs.count

        let projectRoleDTOs: [ProjectRoleDTO] = shouldInclude(.projects) ? collectProjectRoles(modelContext: modelContext, filter: filter) : []
        counts["ProjectRole"] = projectRoleDTOs.count

        let projectWeekDTOs: [ProjectTemplateWeekDTO] = shouldInclude(.projects) ? collectProjectWeeks(modelContext: modelContext, filter: filter) : []
        counts["ProjectTemplateWeek"] = projectWeekDTOs.count

        let projectWeekAssignDTOs: [ProjectWeekRoleAssignmentDTO] = shouldInclude(.projects) ? collectProjectWeekAssignments(modelContext: modelContext, filter: filter) : []
        counts["ProjectWeekRoleAssignment"] = projectWeekAssignDTOs.count

        progress(0.9, "Collecting preferences…")
        let preferences: PreferencesDTO = shouldInclude(.preferences) ? BackupPreferencesService.buildPreferencesDTO() : PreferencesDTO(values: [:])

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            lessonAssignments: [],
            workPlanItems: [],
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: [],
            communityTopics: [],
            proposedSolutions: [],
            communityAttachments: [],
            attendance: attendanceDTOs,
            workCompletions: workCompletionDTOs,
            projects: projectDTOs,
            projectAssignmentTemplates: projectTemplateDTOs,
            projectSessions: projectSessionDTOs,
            projectRoles: projectRoleDTOs,
            projectTemplateWeeks: projectWeekDTOs,
            projectWeekRoleAssignments: projectWeekAssignDTOs,
            preferences: preferences
        )

        return (payload, counts)
    }

    private func collectStudents(modelContext: ModelContext, filter: ExportFilter) -> [StudentDTO] {
        let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
        let filtered = filter.studentIDs != nil ? allStudents.filter { filter.studentIDs!.contains($0.id) } : allStudents
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectLessons(modelContext: ModelContext) -> [LessonDTO] {
        let allLessons = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
        return BackupServiceHelpers.toDTOs(allLessons)
    }

    private func collectStudentLessons(modelContext: ModelContext, filter: ExportFilter) -> [StudentLessonDTO] {
        let allSL = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
        let filtered = allSL.filter { sl in
            if let studentIDs = filter.studentIDs {
                guard sl.resolvedStudentIDs.contains(where: { studentIDs.contains($0) }) else { return false }
            }
            if let range = filter.dateRange {
                return range.contains(sl.createdAt)
            }
            return true
        }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    // MARK: - Collection Helpers

    private func collectNotes(modelContext: ModelContext, filter: ExportFilter) -> [NoteDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.createdAt }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    // Removed: collectPresentations - Presentations are no longer exported; LessonAssignment is used instead

    private func collectNonSchoolDays(modelContext: ModelContext, filter: ExportFilter) -> [NonSchoolDayDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<NonSchoolDay>())) ?? []
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectSchoolDayOverrides(modelContext: ModelContext, filter: ExportFilter) -> [SchoolDayOverrideDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<SchoolDayOverride>())) ?? []
        let filtered = BackupServiceHelpers.filterByDateRange(all, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectAttendance(modelContext: ModelContext, filter: ExportFilter) -> [AttendanceRecordDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<AttendanceRecord>())) ?? []
        var filtered = BackupServiceHelpers.filterByStudents(all, studentIDs: filter.studentIDs) { UUID(uuidString: $0.studentID) }
        filtered = BackupServiceHelpers.filterByDateRange(filtered, dateRange: filter.dateRange) { $0.date }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectWorkCompletions(modelContext: ModelContext, filter: ExportFilter) -> [WorkCompletionRecordDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkCompletionRecord>())) ?? []
        var filtered = BackupServiceHelpers.filterByStudents(all, studentIDs: filter.studentIDs) { UUID(uuidString: $0.studentID) }
        filtered = BackupServiceHelpers.filterByDateRange(filtered, dateRange: filter.dateRange) { $0.completedAt }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjects(modelContext: ModelContext, filter: ExportFilter) -> [ProjectDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { $0.id }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectTemplates(modelContext: ModelContext, filter: ExportFilter) -> [ProjectAssignmentTemplateDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectAssignmentTemplate>())) ?? []
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectSessions(modelContext: ModelContext, filter: ExportFilter) -> [ProjectSessionDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectSession>())) ?? []
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectRoles(modelContext: ModelContext, filter: ExportFilter) -> [ProjectRoleDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectRole>())) ?? []
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectWeeks(modelContext: ModelContext, filter: ExportFilter) -> [ProjectTemplateWeekDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
        let filtered = BackupServiceHelpers.filterByProjects(all, projectIDs: filter.projectIDs) { UUID(uuidString: $0.projectID) }
        return BackupServiceHelpers.toDTOs(filtered)
    }

    private func collectProjectWeekAssignments(modelContext: ModelContext, filter: ExportFilter) -> [ProjectWeekRoleAssignmentDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectWeekRoleAssignment>())) ?? []

        if let projectIDs = filter.projectIDs {
            let weeks = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
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
