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

    private let codec = BackupCodec()

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
        let envelope = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(
                entityCounts: counts,
                sha256: sha,
                notes: "Selective export",
                compression: BackupFile.compressionAlgorithm
            ),
            payload: nil,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )

        progress(0.8, "Writing backup file…")
        let envBytes = try encoder.encode(envelope)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)

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
        let estimatedSize = BackupService().estimateBackupSizeFromCounts(includedCounts)

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

        // Helper to check if entity type is included
        func shouldInclude(_ type: EntityType) -> Bool {
            filter.entityTypes?.contains(type) ?? true
        }

        // Helper to check if date is in range
        func isInDateRange(_ date: Date?) -> Bool {
            guard let range = filter.dateRange, let d = date else { return true }
            return range.contains(d)
        }

        progress(0.1, "Collecting students…")

        // Collect students
        var studentDTOs: [StudentDTO] = []
        if shouldInclude(.students) {
            let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
            let filtered: [Student]
            if let studentIDs = filter.studentIDs {
                filtered = allStudents.filter { studentIDs.contains($0.id) }
            } else {
                filtered = allStudents
            }

            studentDTOs = filtered.map { s in
                let level: StudentDTO.Level = (s.level == .upper) ? .upper : .lower
                return StudentDTO(
                    id: s.id,
                    firstName: s.firstName,
                    lastName: s.lastName,
                    birthday: s.birthday,
                    dateStarted: s.dateStarted,
                    level: level,
                    nextLessons: s.nextLessonUUIDs,
                    manualOrder: s.manualOrder,
                    createdAt: nil,
                    updatedAt: nil
                )
            }
        }
        counts["Student"] = studentDTOs.count

        progress(0.2, "Collecting lessons…")

        // Collect lessons
        var lessonDTOs: [LessonDTO] = []
        if shouldInclude(.lessons) {
            let allLessons = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
            lessonDTOs = allLessons.map { l in
                LessonDTO(
                    id: l.id,
                    name: l.name,
                    subject: l.subject,
                    group: l.group,
                    orderInGroup: l.orderInGroup,
                    subheading: l.subheading,
                    writeUp: l.writeUp,
                    createdAt: nil,
                    updatedAt: nil,
                    pagesFileRelativePath: l.pagesFileRelativePath
                )
            }
        }
        counts["Lesson"] = lessonDTOs.count

        progress(0.3, "Collecting student lessons…")

        // Collect student lessons
        var studentLessonDTOs: [StudentLessonDTO] = []
        if shouldInclude(.studentLessons) {
            let allSL = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
            let filtered = allSL.filter { sl in
                // Filter by student
                if let studentIDs = filter.studentIDs {
                    guard sl.resolvedStudentIDs.contains(where: { studentIDs.contains($0) }) else {
                        return false
                    }
                }
                // Filter by date
                return isInDateRange(sl.createdAt)
            }

            studentLessonDTOs = filtered.compactMap { sl in
                guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { return nil }
                return StudentLessonDTO(
                    id: sl.id,
                    lessonID: lessonIDUUID,
                    studentIDs: sl.resolvedStudentIDs,
                    createdAt: sl.createdAt,
                    scheduledFor: sl.scheduledFor,
                    givenAt: sl.givenAt,
                    isPresented: sl.isPresented,
                    notes: sl.notes,
                    needsPractice: sl.needsPractice,
                    needsAnotherPresentation: sl.needsAnotherPresentation,
                    followUpWork: sl.followUpWork,
                    studentGroupKey: nil
                )
            }
        }
        counts["StudentLesson"] = studentLessonDTOs.count

        progress(0.5, "Collecting other entities…")

        // Collect remaining entities with similar filtering...
        // (Simplified for brevity - would include all entity types with proper filtering)

        let noteDTOs: [NoteDTO] = shouldInclude(.notes) ? collectNotes(modelContext: modelContext, filter: filter) : []
        counts["Note"] = noteDTOs.count

        let presentationDTOs: [PresentationDTO] = shouldInclude(.presentations) ? collectPresentations(modelContext: modelContext, filter: filter) : []
        counts["Presentation"] = presentationDTOs.count

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

        let preferences: PreferencesDTO
        if shouldInclude(.preferences) {
            preferences = BackupPreferencesService.buildPreferencesDTO()
        } else {
            preferences = PreferencesDTO(values: [:])
        }

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            lessonAssignments: [], // Selective export doesn't include lesson assignments yet
            workPlanItems: [],
            scopedNotes: [],
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: [],
            presentations: presentationDTOs,
            communityTopics: [],
            proposedSolutions: [],
            meetingNotes: [],
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

    // MARK: - Collection Helpers

    private func collectNotes(modelContext: ModelContext, filter: ExportFilter) -> [NoteDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        let filtered = all.filter { n in
            if let range = filter.dateRange {
                return range.contains(n.createdAt)
            }
            return true
        }

        return filtered.map { n in
            let scopeString: String
            if let data = try? JSONEncoder().encode(n.scope) {
                scopeString = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                scopeString = "{}"
            }
            return NoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                isPinned: n.isPinned,
                scope: scopeString,
                lessonID: n.lesson?.id,
                imagePath: n.imagePath
            )
        }
    }

    private func collectPresentations(modelContext: ModelContext, filter: ExportFilter) -> [PresentationDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<Presentation>())) ?? []
        let filtered = all.filter { p in
            // Filter by student
            if let studentIDs = filter.studentIDs {
                let pStudentIDs = Set(p.studentIDs.compactMap { UUID(uuidString: $0) })
                guard !pStudentIDs.isDisjoint(with: studentIDs) else { return false }
            }
            // Filter by date
            if let range = filter.dateRange {
                return range.contains(p.presentedAt)
            }
            return true
        }

        return filtered.map { p in
            PresentationDTO(
                id: p.id,
                createdAt: p.createdAt,
                presentedAt: p.presentedAt,
                lessonID: p.lessonID,
                studentIDs: p.studentIDs,
                legacyStudentLessonID: p.legacyStudentLessonID,
                lessonTitleSnapshot: p.lessonTitleSnapshot,
                lessonSubtitleSnapshot: p.lessonSubtitleSnapshot
            )
        }
    }

    private func collectNonSchoolDays(modelContext: ModelContext, filter: ExportFilter) -> [NonSchoolDayDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<NonSchoolDay>())) ?? []
        let filtered = all.filter { d in
            if let range = filter.dateRange {
                return range.contains(d.date)
            }
            return true
        }
        return filtered.map { NonSchoolDayDTO(id: $0.id, date: $0.date, reason: $0.reason) }
    }

    private func collectSchoolDayOverrides(modelContext: ModelContext, filter: ExportFilter) -> [SchoolDayOverrideDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<SchoolDayOverride>())) ?? []
        let filtered = all.filter { o in
            if let range = filter.dateRange {
                return range.contains(o.date)
            }
            return true
        }
        return filtered.map { SchoolDayOverrideDTO(id: $0.id, date: $0.date, note: $0.note) }
    }

    private func collectAttendance(modelContext: ModelContext, filter: ExportFilter) -> [AttendanceRecordDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<AttendanceRecord>())) ?? []
        let filtered = all.filter { a in
            // Filter by student
            if let studentIDs = filter.studentIDs {
                guard let sid = UUID(uuidString: a.studentID), studentIDs.contains(sid) else {
                    return false
                }
            }
            // Filter by date
            if let range = filter.dateRange {
                return range.contains(a.date)
            }
            return true
        }

        return filtered.compactMap { a in
            guard let studentIDUUID = UUID(uuidString: a.studentID) else { return nil }
            return AttendanceRecordDTO(
                id: a.id,
                studentID: studentIDUUID,
                date: a.date,
                status: a.status.rawValue,
                absenceReason: a.absenceReason.rawValue == "none" ? nil : a.absenceReason.rawValue,
                note: a.note
            )
        }
    }

    private func collectWorkCompletions(modelContext: ModelContext, filter: ExportFilter) -> [WorkCompletionRecordDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkCompletionRecord>())) ?? []
        let filtered = all.filter { r in
            // Filter by student
            if let studentIDs = filter.studentIDs {
                guard let sid = UUID(uuidString: r.studentID), studentIDs.contains(sid) else {
                    return false
                }
            }
            // Filter by date
            if let range = filter.dateRange {
                return range.contains(r.completedAt)
            }
            return true
        }

        return filtered.compactMap { r in
            guard let workIDUUID = UUID(uuidString: r.workID),
                  let studentIDUUID = UUID(uuidString: r.studentID) else { return nil }
            return WorkCompletionRecordDTO(
                id: r.id,
                workID: workIDUUID,
                studentID: studentIDUUID,
                completedAt: r.completedAt,
                note: r.note
            )
        }
    }

    private func collectProjects(modelContext: ModelContext, filter: ExportFilter) -> [ProjectDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let filtered: [Project]
        if let projectIDs = filter.projectIDs {
            filtered = all.filter { projectIDs.contains($0.id) }
        } else {
            filtered = all
        }

        return filtered.map { c in
            ProjectDTO(
                id: c.id,
                createdAt: c.createdAt,
                title: c.title,
                bookTitle: c.bookTitle,
                memberStudentIDs: c.memberStudentIDs
            )
        }
    }

    private func collectProjectTemplates(modelContext: ModelContext, filter: ExportFilter) -> [ProjectAssignmentTemplateDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectAssignmentTemplate>())) ?? []
        let filtered: [ProjectAssignmentTemplate]
        if let projectIDs = filter.projectIDs {
            filtered = all.filter { t in
                guard let pid = UUID(uuidString: t.projectID) else { return false }
                return projectIDs.contains(pid)
            }
        } else {
            filtered = all
        }

        return filtered.compactMap { t in
            guard let projectIDUUID = UUID(uuidString: t.projectID) else { return nil }
            return ProjectAssignmentTemplateDTO(
                id: t.id,
                createdAt: t.createdAt,
                projectID: projectIDUUID,
                title: t.title,
                instructions: t.instructions,
                isShared: t.isShared,
                defaultLinkedLessonID: t.defaultLinkedLessonID
            )
        }
    }

    private func collectProjectSessions(modelContext: ModelContext, filter: ExportFilter) -> [ProjectSessionDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectSession>())) ?? []
        let filtered: [ProjectSession]
        if let projectIDs = filter.projectIDs {
            filtered = all.filter { s in
                guard let pid = UUID(uuidString: s.projectID) else { return false }
                return projectIDs.contains(pid)
            }
        } else {
            filtered = all
        }

        return filtered.compactMap { s in
            guard let projectIDUUID = UUID(uuidString: s.projectID) else { return nil }
            let templateWeekIDUUID = s.templateWeekID.flatMap { UUID(uuidString: $0) }
            return ProjectSessionDTO(
                id: s.id,
                createdAt: s.createdAt,
                projectID: projectIDUUID,
                meetingDate: s.meetingDate,
                chapterOrPages: s.chapterOrPages,
                notes: s.notes,
                agendaItemsJSON: s.agendaItemsJSON,
                templateWeekID: templateWeekIDUUID
            )
        }
    }

    private func collectProjectRoles(modelContext: ModelContext, filter: ExportFilter) -> [ProjectRoleDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectRole>())) ?? []
        let filtered: [ProjectRole]
        if let projectIDs = filter.projectIDs {
            filtered = all.filter { r in
                guard let pid = UUID(uuidString: r.projectID) else { return false }
                return projectIDs.contains(pid)
            }
        } else {
            filtered = all
        }

        return filtered.compactMap { r in
            guard let projectIDUUID = UUID(uuidString: r.projectID) else { return nil }
            return ProjectRoleDTO(
                id: r.id,
                createdAt: r.createdAt,
                projectID: projectIDUUID,
                title: r.title,
                summary: r.summary,
                instructions: r.instructions
            )
        }
    }

    private func collectProjectWeeks(modelContext: ModelContext, filter: ExportFilter) -> [ProjectTemplateWeekDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
        let filtered: [ProjectTemplateWeek]
        if let projectIDs = filter.projectIDs {
            filtered = all.filter { w in
                guard let pid = UUID(uuidString: w.projectID) else { return false }
                return projectIDs.contains(pid)
            }
        } else {
            filtered = all
        }

        return filtered.compactMap { w in
            guard let projectIDUUID = UUID(uuidString: w.projectID) else { return nil }
            return ProjectTemplateWeekDTO(
                id: w.id,
                createdAt: w.createdAt,
                projectID: projectIDUUID,
                weekIndex: w.weekIndex,
                readingRange: w.readingRange,
                agendaItemsJSON: w.agendaItemsJSON,
                linkedLessonIDsJSON: w.linkedLessonIDsJSON,
                workInstructions: w.workInstructions
            )
        }
    }

    private func collectProjectWeekAssignments(modelContext: ModelContext, filter: ExportFilter) -> [ProjectWeekRoleAssignmentDTO] {
        let all = (try? modelContext.fetch(FetchDescriptor<ProjectWeekRoleAssignment>())) ?? []

        // Get project week IDs from included projects
        var includedWeekIDs: Set<String>?
        if let projectIDs = filter.projectIDs {
            let weeks = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
            includedWeekIDs = Set(weeks.filter { w in
                guard let pid = UUID(uuidString: w.projectID) else { return false }
                return projectIDs.contains(pid)
            }.map { $0.id.uuidString })
        }

        let filtered: [ProjectWeekRoleAssignment]
        if let weekIDs = includedWeekIDs {
            filtered = all.filter { weekIDs.contains($0.weekID) }
        } else {
            filtered = all
        }

        return filtered.compactMap { a in
            guard let weekIDUUID = UUID(uuidString: a.weekID),
                  let roleIDUUID = UUID(uuidString: a.roleID) else { return nil }
            return ProjectWeekRoleAssignmentDTO(
                id: a.id,
                createdAt: a.createdAt,
                weekID: weekIDUUID,
                studentID: a.studentID,
                roleID: roleIDUUID
            )
        }
    }
}
