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
        let warning = ""

        switch type {
        case .students:
            // Use cached lookup - O(1) instead of O(n) per entity
            let result = BackupEntityImporter.importStudents(
                payload.students,
                into: modelContext,
                existingCheck: { [studentsByID] id in studentsByID[id] }
            )
            // Update cache with newly imported students
            for (id, student) in result {
                studentsByID[id] = student
            }
            imported = result.count
            skipped = payload.students.count - result.count

        case .lessons:
            let existingLessonIDs = Set(lessonsByID.keys)
            BackupEntityImporter.importLessons(
                payload.lessons,
                into: modelContext,
                existingCheck: { [lessonsByID] id in lessonsByID[id] }
            )
            // Track imported count
            let newLessons = payload.lessons.filter { !existingLessonIDs.contains($0.id) }
            imported = newLessons.count
            skipped = payload.lessons.count - newLessons.count
            // Refresh lesson cache for subsequent imports
            let allLessons = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
            lessonsByID = allLessons.toDictionary(by: \.id)

        case .studentLessons:
            BackupEntityImporter.importStudentLessons(
                payload.studentLessons,
                into: modelContext,
                studentLessonCheck: { [existingStudentLessonIDs] id in
                    // Return a placeholder if exists (importer only checks for nil)
                    existingStudentLessonIDs.contains(id) ? StudentLesson(lessonID: id, studentIDs: []) : nil
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] },
                studentCheck: { [studentsByID] id in studentsByID[id] }
            )
            imported = payload.studentLessons.count

        case .workPlanItems:
            BackupEntityImporter.importWorkPlanItems(
                payload.workPlanItems,
                into: modelContext,
                existingCheck: { [existingWorkPlanItemIDs] id in
                    existingWorkPlanItemIDs.contains(id) ? WorkPlanItem(workID: id, scheduledDate: Date(), reason: nil, note: nil) : nil
                }
            )
            imported = payload.workPlanItems.count

        case .notes:
            BackupEntityImporter.importNotes(
                payload.notes,
                into: modelContext,
                existingCheck: { [existingNoteIDs] id in
                    existingNoteIDs.contains(id) ? Note(body: "", scope: .all) : nil
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] }
            )
            imported = payload.notes.count

        case .calendar:
            BackupEntityImporter.importNonSchoolDays(
                payload.nonSchoolDays,
                into: modelContext,
                existingCheck: { [existingNonSchoolDayIDs] id in
                    existingNonSchoolDayIDs.contains(id) ? NonSchoolDay(date: Date()) : nil
                }
            )
            BackupEntityImporter.importSchoolDayOverrides(
                payload.schoolDayOverrides,
                into: modelContext,
                existingCheck: { [existingSchoolDayOverrideIDs] id in
                    existingSchoolDayOverrideIDs.contains(id) ? SchoolDayOverride(date: Date()) : nil
                }
            )
            imported = payload.nonSchoolDays.count + payload.schoolDayOverrides.count

        case .meetings:
            BackupEntityImporter.importStudentMeetings(
                payload.studentMeetings,
                into: modelContext,
                existingCheck: { [existingMeetingIDs] id in
                    existingMeetingIDs.contains(id) ? StudentMeeting(studentID: UUID(), date: Date()) : nil
                }
            )
            imported = payload.studentMeetings.count

        case .presentations:
            // Import old Presentations as LessonAssignments (backward compatibility)
            let allStudentLessons = (try? modelContext.fetch(FetchDescriptor<StudentLesson>())) ?? []
            BackupEntityImporter.importPresentationsAsLessonAssignments(
                payload.presentations,
                into: modelContext,
                existingLessonAssignmentCheck: { [existingLessonAssignmentIDs] id in
                    existingLessonAssignmentIDs.contains(id) ? LessonAssignment(state: .draft, lessonID: UUID(), studentIDs: []) : nil
                },
                allStudentLessons: allStudentLessons
            )
            imported = payload.presentations.count

        case .community:
            BackupEntityImporter.importCommunityTopics(
                payload.communityTopics,
                into: modelContext,
                existingCheck: { [topicsByID] id in topicsByID[id] }
            )
            // Refresh topic cache for subsequent imports
            let allTopics = (try? modelContext.fetch(FetchDescriptor<CommunityTopic>())) ?? []
            topicsByID = allTopics.toDictionary(by: \.id)

            BackupEntityImporter.importProposedSolutions(
                payload.proposedSolutions,
                into: modelContext,
                existingCheck: { [existingSolutionIDs] id in
                    existingSolutionIDs.contains(id) ? ProposedSolution(title: "", details: "", proposedBy: "", topic: nil) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            BackupEntityImporter.importCommunityAttachments(
                payload.communityAttachments,
                into: modelContext,
                existingCheck: { [existingAttachmentIDs] id in
                    existingAttachmentIDs.contains(id) ? CommunityAttachment(filename: "", kind: .file, data: nil, topic: nil) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            imported = payload.communityTopics.count + payload.proposedSolutions.count + payload.communityAttachments.count

        case .attendance:
            BackupEntityImporter.importAttendanceRecords(
                payload.attendance,
                into: modelContext,
                existingCheck: { [existingAttendanceIDs] id in
                    existingAttendanceIDs.contains(id) ? AttendanceRecord(studentID: UUID(), date: Date(), status: .unmarked) : nil
                }
            )
            imported = payload.attendance.count

        case .workCompletions:
            BackupEntityImporter.importWorkCompletionRecords(
                payload.workCompletions,
                into: modelContext,
                existingCheck: { [existingWorkCompletionIDs] id in
                    existingWorkCompletionIDs.contains(id) ? WorkCompletionRecord(workID: UUID(), studentID: UUID(), completedAt: Date()) : nil
                }
            )
            imported = payload.workCompletions.count

        case .projects:
            BackupEntityImporter.importProjects(
                payload.projects,
                into: modelContext,
                existingCheck: { [existingProjectIDs] id in
                    existingProjectIDs.contains(id) ? Project(title: "", bookTitle: nil, memberStudentIDs: []) : nil
                }
            )
            BackupEntityImporter.importProjectRoles(
                payload.projectRoles,
                into: modelContext,
                existingCheck: { [existingProjectRoleIDs] id in
                    existingProjectRoleIDs.contains(id) ? ProjectRole(projectID: UUID(), title: "", summary: "", instructions: "") : nil
                }
            )
            BackupEntityImporter.importProjectTemplateWeeks(
                payload.projectTemplateWeeks,
                into: modelContext,
                existingCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
            )
            // Refresh template weeks cache for subsequent imports
            let allWeeks = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
            templateWeeksByID = allWeeks.toDictionary(by: \.id)

            BackupEntityImporter.importProjectAssignmentTemplates(
                payload.projectAssignmentTemplates,
                into: modelContext,
                existingCheck: { [existingProjectAssignmentTemplateIDs] id in
                    existingProjectAssignmentTemplateIDs.contains(id) ? ProjectAssignmentTemplate(projectID: UUID(), title: "", instructions: "") : nil
                }
            )
            BackupEntityImporter.importProjectWeekRoleAssignments(
                payload.projectWeekRoleAssignments,
                into: modelContext,
                existingCheck: { [existingProjectWeekRoleAssignmentIDs] id in
                    existingProjectWeekRoleAssignmentIDs.contains(id) ? ProjectWeekRoleAssignment(weekID: UUID(), studentID: "", roleID: UUID(), week: nil) : nil
                },
                weekCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
            )
            BackupEntityImporter.importProjectSessions(
                payload.projectSessions,
                into: modelContext,
                existingCheck: { [existingProjectSessionIDs] id in
                    existingProjectSessionIDs.contains(id) ? ProjectSession(projectID: UUID(), meetingDate: Date()) : nil
                }
            )
            imported = payload.projects.count + payload.projectAssignmentTemplates.count +
                payload.projectSessions.count + payload.projectRoles.count +
                payload.projectTemplateWeeks.count + payload.projectWeekRoleAssignments.count
        }

        return (imported, skipped, warning)
    }

    // MARK: - Entity Lookup Caches

    /// Lookup dictionaries for entities that need to be linked during import.
    /// These provide O(1) access by ID instead of repeated database queries.
    private var studentsByID: [UUID: Student] = [:]
    private var lessonsByID: [UUID: Lesson] = [:]
    private var topicsByID: [UUID: CommunityTopic] = [:]
    private var templateWeeksByID: [UUID: ProjectTemplateWeek] = [:]

    /// ID sets for simple existence checks (no entity retrieval needed)
    private var existingStudentLessonIDs: Set<UUID> = []
    private var existingNoteIDs: Set<UUID> = []
    private var existingWorkPlanItemIDs: Set<UUID> = []
    private var existingNonSchoolDayIDs: Set<UUID> = []
    private var existingSchoolDayOverrideIDs: Set<UUID> = []
    private var existingMeetingIDs: Set<UUID> = []
    private var existingLessonAssignmentIDs: Set<UUID> = []
    private var existingSolutionIDs: Set<UUID> = []
    private var existingAttachmentIDs: Set<UUID> = []
    private var existingAttendanceIDs: Set<UUID> = []
    private var existingWorkCompletionIDs: Set<UUID> = []
    private var existingProjectIDs: Set<UUID> = []
    private var existingProjectRoleIDs: Set<UUID> = []
    private var existingProjectAssignmentTemplateIDs: Set<UUID> = []
    private var existingProjectWeekRoleAssignmentIDs: Set<UUID> = []
    private var existingProjectSessionIDs: Set<UUID> = []

    /// Pre-builds lookup caches for all entity types to enable O(1) existence checks.
    /// This is much faster than querying the database for each entity.
    private func buildExistingIDCaches(in context: ModelContext) {
        // Build lookup dictionaries for entities needed for relationship linking
        let students = (try? context.fetch(FetchDescriptor<Student>())) ?? []
        studentsByID = students.toDictionary(by: \.id)

        let lessons = (try? context.fetch(FetchDescriptor<Lesson>())) ?? []
        lessonsByID = lessons.toDictionary(by: \.id)

        let topics = (try? context.fetch(FetchDescriptor<CommunityTopic>())) ?? []
        topicsByID = topics.toDictionary(by: \.id)

        let weeks = (try? context.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
        templateWeeksByID = weeks.toDictionary(by: \.id)

        // Build ID sets for simple existence checks
        existingStudentLessonIDs = Set((try? context.fetch(FetchDescriptor<StudentLesson>()))?.map { $0.id } ?? [])
        existingNoteIDs = Set((try? context.fetch(FetchDescriptor<Note>()))?.map { $0.id } ?? [])
        existingWorkPlanItemIDs = Set((try? context.fetch(FetchDescriptor<WorkPlanItem>()))?.map { $0.id } ?? [])
        existingNonSchoolDayIDs = Set((try? context.fetch(FetchDescriptor<NonSchoolDay>()))?.map { $0.id } ?? [])
        existingSchoolDayOverrideIDs = Set((try? context.fetch(FetchDescriptor<SchoolDayOverride>()))?.map { $0.id } ?? [])
        existingMeetingIDs = Set((try? context.fetch(FetchDescriptor<StudentMeeting>()))?.map { $0.id } ?? [])
        existingLessonAssignmentIDs = Set((try? context.fetch(FetchDescriptor<LessonAssignment>()))?.map { $0.id } ?? [])
        existingSolutionIDs = Set((try? context.fetch(FetchDescriptor<ProposedSolution>()))?.map { $0.id } ?? [])
        existingAttachmentIDs = Set((try? context.fetch(FetchDescriptor<CommunityAttachment>()))?.map { $0.id } ?? [])
        existingAttendanceIDs = Set((try? context.fetch(FetchDescriptor<AttendanceRecord>()))?.map { $0.id } ?? [])
        existingWorkCompletionIDs = Set((try? context.fetch(FetchDescriptor<WorkCompletionRecord>()))?.map { $0.id } ?? [])
        existingProjectIDs = Set((try? context.fetch(FetchDescriptor<Project>()))?.map { $0.id } ?? [])
        existingProjectRoleIDs = Set((try? context.fetch(FetchDescriptor<ProjectRole>()))?.map { $0.id } ?? [])
        existingProjectAssignmentTemplateIDs = Set((try? context.fetch(FetchDescriptor<ProjectAssignmentTemplate>()))?.map { $0.id } ?? [])
        existingProjectWeekRoleAssignmentIDs = Set((try? context.fetch(FetchDescriptor<ProjectWeekRoleAssignment>()))?.map { $0.id } ?? [])
        existingProjectSessionIDs = Set((try? context.fetch(FetchDescriptor<ProjectSession>()))?.map { $0.id } ?? [])
    }

    /// Clears the lookup caches to free memory after restore is complete
    private func clearIDCaches() {
        studentsByID = [:]
        lessonsByID = [:]
        topicsByID = [:]
        templateWeeksByID = [:]
        existingStudentLessonIDs = []
        existingNoteIDs = []
        existingWorkPlanItemIDs = []
        existingNonSchoolDayIDs = []
        existingSchoolDayOverrideIDs = []
        existingMeetingIDs = []
        existingLessonAssignmentIDs = []
        existingSolutionIDs = []
        existingAttachmentIDs = []
        existingAttendanceIDs = []
        existingWorkCompletionIDs = []
        existingProjectIDs = []
        existingProjectRoleIDs = []
        existingProjectAssignmentTemplateIDs = []
        existingProjectWeekRoleAssignmentIDs = []
        existingProjectSessionIDs = []
    }
}
