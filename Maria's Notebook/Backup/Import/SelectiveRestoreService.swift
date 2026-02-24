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
        case notes = "Notes"
        case calendar = "Calendar (Non-School Days & Overrides)"
        case meetings = "Student Meetings"
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
            case .notes: return "note.text"
            case .calendar: return "calendar"
            case .meetings: return "person.2.wave.2"
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
            case .community: return []
            case .notes: return [.lessons]
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

    private let backupService: BackupService
    private let codec = BackupCodec()
    
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
        counts[.studentLessons] = payload.studentLessons.count
        counts[.notes] = payload.notes.count
        counts[.calendar] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
        counts[.meetings] = payload.studentMeetings.count
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
            case .notes:
                counts[type] = payload.notes.count
            case .calendar:
                counts[type] = payload.nonSchoolDays.count + payload.schoolDayOverrides.count
            case .meetings:
                counts[type] = payload.studentMeetings.count
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
            .students, .lessons, .studentLessons,
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
            do {
                let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                lessonsByID = allLessons.toDictionary(by: \.id)
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to refresh lesson cache: \(error)")
            }

        case .studentLessons:
            BackupEntityImporter.importStudentLessons(
                payload.studentLessons,
                into: modelContext,
                studentLessonCheck: { [self] id in
                    // Return a lightweight instance only to signal existence.
                    self.getCachedIDs("studentLessons").contains(id) ? StudentLesson(lessonID: id, studentIDs: []) : nil
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] },
                studentCheck: { [studentsByID] id in studentsByID[id] }
            )
            imported = payload.studentLessons.count

        case .notes:
            BackupEntityImporter.importNotes(
                payload.notes,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("notes").contains(id) ? Note(body: "", scope: .all) : nil
                },
                lessonCheck: { [lessonsByID] id in lessonsByID[id] }
            )
            imported = payload.notes.count

        case .calendar:
            BackupEntityImporter.importNonSchoolDays(
                payload.nonSchoolDays,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("nonSchoolDays").contains(id) ? NonSchoolDay(date: Date()) : nil
                }
            )
            BackupEntityImporter.importSchoolDayOverrides(
                payload.schoolDayOverrides,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("schoolDayOverrides").contains(id) ? SchoolDayOverride(date: Date()) : nil
                }
            )
            imported = payload.nonSchoolDays.count + payload.schoolDayOverrides.count

        case .meetings:
            BackupEntityImporter.importStudentMeetings(
                payload.studentMeetings,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("studentMeetings").contains(id) ? StudentMeeting(studentID: UUID(), date: Date()) : nil
                }
            )
            imported = payload.studentMeetings.count

        case .community:
            BackupEntityImporter.importCommunityTopics(
                payload.communityTopics,
                into: modelContext,
                existingCheck: { [topicsByID] id in topicsByID[id] }
            )
            // Refresh topic cache for subsequent imports
            do {
                let allTopics = try modelContext.fetch(FetchDescriptor<CommunityTopic>())
                topicsByID = allTopics.toDictionary(by: \.id)
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to refresh topic cache: \(error)")
            }

            BackupEntityImporter.importProposedSolutions(
                payload.proposedSolutions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("proposedSolutions").contains(id) ? ProposedSolution(title: "", details: "", proposedBy: "", topic: nil) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            BackupEntityImporter.importCommunityAttachments(
                payload.communityAttachments,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("communityAttachments").contains(id) ? CommunityAttachment(filename: "", kind: .file, data: nil, topic: nil) : nil
                },
                topicCheck: { [topicsByID] id in topicsByID[id] }
            )
            imported = payload.communityTopics.count + payload.proposedSolutions.count + payload.communityAttachments.count

        case .attendance:
            BackupEntityImporter.importAttendanceRecords(
                payload.attendance,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("attendanceRecords").contains(id) ? AttendanceRecord(studentID: UUID(), date: Date(), status: .unmarked) : nil
                }
            )
            imported = payload.attendance.count

        case .workCompletions:
            BackupEntityImporter.importWorkCompletionRecords(
                payload.workCompletions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("workCompletionRecords").contains(id) ? WorkCompletionRecord(workID: UUID(), studentID: UUID(), completedAt: Date()) : nil
                }
            )
            imported = payload.workCompletions.count

        case .projects:
            BackupEntityImporter.importProjects(
                payload.projects,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projects").contains(id) ? Project(title: "", bookTitle: nil, memberStudentIDs: []) : nil
                }
            )
            BackupEntityImporter.importProjectRoles(
                payload.projectRoles,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectRoles").contains(id) ? ProjectRole(projectID: UUID(), title: "", summary: "", instructions: "") : nil
                }
            )
            BackupEntityImporter.importProjectTemplateWeeks(
                payload.projectTemplateWeeks,
                into: modelContext,
                existingCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
            )
            // Refresh template weeks cache for subsequent imports
            do {
                let allWeeks = try modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())
                templateWeeksByID = allWeeks.toDictionary(by: \.id)
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to refresh template weeks cache: \(error)")
            }

            BackupEntityImporter.importProjectAssignmentTemplates(
                payload.projectAssignmentTemplates,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectAssignmentTemplates").contains(id) ? ProjectAssignmentTemplate(projectID: UUID(), title: "", instructions: "") : nil
                }
            )
            BackupEntityImporter.importProjectWeekRoleAssignments(
                payload.projectWeekRoleAssignments,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectWeekRoleAssignments").contains(id) ? ProjectWeekRoleAssignment(weekID: UUID(), studentID: "", roleID: UUID(), week: nil) : nil
                },
                weekCheck: { [templateWeeksByID] id in templateWeeksByID[id] }
            )
            BackupEntityImporter.importProjectSessions(
                payload.projectSessions,
                into: modelContext,
                existingCheck: { [self] id in
                    self.getCachedIDs("projectSessions").contains(id) ? ProjectSession(projectID: UUID(), meetingDate: Date()) : nil
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
    private var existingIDSets: [String: Set<UUID>] = [:]

    // MARK: - Cache Helpers

    /// Helper to fetch and cache entity IDs for a given type.
    private func cacheEntityIDs<T: PersistentModel & Identifiable>(_ type: T.Type, key: String, in context: ModelContext) where T.ID == UUID {
        do {
            let entities = try context.fetch(FetchDescriptor<T>())
            existingIDSets[key] = Set(entities.map { $0.id })
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to cache entity IDs for \(key): \(error)")
            existingIDSets[key] = []
        }
    }

    /// Helper to fetch and cache entities with full objects for relationships.
    private func cacheDictionary<T: PersistentModel & Identifiable>(_ type: T.Type, in context: ModelContext) -> [UUID: T] where T.ID == UUID {
        do {
            let entities = try context.fetch(FetchDescriptor<T>())
            return entities.toDictionary(by: \.id)
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to cache dictionary for \(T.self): \(error)")
            return [:]
        }
    }

    /// Helper to get cached ID set.
    private func getCachedIDs(_ key: String) -> Set<UUID> {
        return existingIDSets[key] ?? []
    }

    /// Pre-builds lookup caches for all entity types to enable O(1) existence checks.
    /// This is much faster than querying the database for each entity.
    private func buildExistingIDCaches(in context: ModelContext) {
        // Build lookup dictionaries for entities needed for relationship linking
        studentsByID = cacheDictionary(Student.self, in: context)
        lessonsByID = cacheDictionary(Lesson.self, in: context)
        topicsByID = cacheDictionary(CommunityTopic.self, in: context)
        templateWeeksByID = cacheDictionary(ProjectTemplateWeek.self, in: context)

        // Build ID sets for simple existence checks
        cacheEntityIDs(StudentLesson.self, key: "studentLessons", in: context)
        cacheEntityIDs(Note.self, key: "notes", in: context)
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        cacheEntityIDs(NonSchoolDay.self, key: "nonSchoolDays", in: context)
        cacheEntityIDs(SchoolDayOverride.self, key: "schoolDayOverrides", in: context)
        cacheEntityIDs(StudentMeeting.self, key: "studentMeetings", in: context)
        cacheEntityIDs(LessonAssignment.self, key: "lessonAssignments", in: context)
        cacheEntityIDs(ProposedSolution.self, key: "proposedSolutions", in: context)
        cacheEntityIDs(CommunityAttachment.self, key: "communityAttachments", in: context)
        cacheEntityIDs(AttendanceRecord.self, key: "attendanceRecords", in: context)
        cacheEntityIDs(WorkCompletionRecord.self, key: "workCompletionRecords", in: context)
        cacheEntityIDs(Project.self, key: "projects", in: context)
        cacheEntityIDs(ProjectRole.self, key: "projectRoles", in: context)
        cacheEntityIDs(ProjectAssignmentTemplate.self, key: "projectAssignmentTemplates", in: context)
        cacheEntityIDs(ProjectWeekRoleAssignment.self, key: "projectWeekRoleAssignments", in: context)
        cacheEntityIDs(ProjectSession.self, key: "projectSessions", in: context)
    }

    /// Clears the lookup caches to free memory after restore is complete
    private func clearIDCaches() {
        studentsByID = [:]
        lessonsByID = [:]
        topicsByID = [:]
        templateWeeksByID = [:]
        existingIDSets = [:]
    }
}
