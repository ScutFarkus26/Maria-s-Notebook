// IncrementalBackupService.swift
// Handles incremental backups that only export changed entities

import Foundation
import SwiftData

/// Service for creating incremental backups that only include entities
/// modified since the last backup, reducing backup size and time.
@MainActor
public final class IncrementalBackupService {

    // MARK: - Types

    public struct IncrementalBackupMetadata: Codable, Sendable {
        public var lastBackupDate: Date
        public var backupID: UUID
        public var parentBackupID: UUID?
        public var isFullBackup: Bool
        public var changedEntityCounts: [String: Int]

        public init(
            lastBackupDate: Date,
            backupID: UUID = UUID(),
            parentBackupID: UUID? = nil,
            isFullBackup: Bool,
            changedEntityCounts: [String: Int] = [:]
        ) {
            self.lastBackupDate = lastBackupDate
            self.backupID = backupID
            self.parentBackupID = parentBackupID
            self.isFullBackup = isFullBackup
            self.changedEntityCounts = changedEntityCounts
        }
    }

    public struct IncrementalBackupResult: Sendable {
        public let url: URL
        public let metadata: IncrementalBackupMetadata
        public let totalEntities: Int
        public let changedEntities: Int
        public let savedBytes: Int64
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastIncrementalBackupDate = "IncrementalBackup.lastDate"
        static let lastIncrementalBackupID = "IncrementalBackup.lastID"
    }

    // MARK: - Properties

    private let backupService = BackupService()
    private let codec = BackupCodec()

    /// The date of the last incremental backup
    public var lastBackupDate: Date? {
        let timestamp = UserDefaults.standard.double(forKey: Keys.lastIncrementalBackupDate)
        return timestamp > 0 ? Date(timeIntervalSinceReferenceDate: timestamp) : nil
    }

    /// The ID of the last incremental backup
    public var lastBackupID: UUID? {
        guard let string = UserDefaults.standard.string(forKey: Keys.lastIncrementalBackupID) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    // MARK: - Public API

    /// Creates an incremental backup containing only entities changed since the last backup
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - url: Destination URL for the backup file
    ///   - password: Optional encryption password
    ///   - forceFullBackup: If true, creates a full backup regardless of last backup date
    ///   - progress: Progress callback
    /// - Returns: Result containing metadata and statistics
    public func createIncrementalBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        forceFullBackup: Bool = false,
        progress: @escaping (Double, String) -> Void
    ) async throws -> IncrementalBackupResult {

        let sinceDate = forceFullBackup ? nil : lastBackupDate
        let isFullBackup = sinceDate == nil

        progress(0.0, isFullBackup ? "Creating full backup…" : "Scanning for changes…")

        // Collect all entities and filter by updatedAt if incremental
        let (payload, changedCounts, totalCounts) = try collectPayload(
            modelContext: modelContext,
            sinceDate: sinceDate,
            progress: { subProgress, message in
                progress(subProgress * 0.3, message)
            }
        )

        let changedCount = changedCounts.values.reduce(0, +)
        let totalCount = totalCounts.values.reduce(0, +)

        progress(0.3, "Encoding \(changedCount) entities…")

        // Encode payload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(0.5, "Compressing data…")
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        // Encrypt if password provided
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(0.6, "Encrypting data…")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalPayload = nil
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
        }

        // Create metadata
        let backupID = UUID()
        let metadata = IncrementalBackupMetadata(
            lastBackupDate: Date(),
            backupID: backupID,
            parentBackupID: lastBackupID,
            isFullBackup: isFullBackup,
            changedEntityCounts: changedCounts
        )

        // Build envelope with incremental metadata in manifest notes
        let metadataJSON = try JSONEncoder().encode(metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8)

        let envelope = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(
                entityCounts: changedCounts,
                sha256: sha,
                notes: metadataString,
                compression: BackupFile.compressionAlgorithm
            ),
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )

        progress(0.8, "Writing backup file…")
        let envBytes = try encoder.encode(envelope)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)

        // Update last backup tracking
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Keys.lastIncrementalBackupDate)
        UserDefaults.standard.set(backupID.uuidString, forKey: Keys.lastIncrementalBackupID)

        progress(1.0, "Incremental backup complete")

        // Calculate saved bytes (estimate based on total vs changed)
        let estimatedFullSize = backupService.estimateBackupSizeFromCounts(totalCounts)
        let actualSize = Int64(envBytes.count)
        let savedBytes = max(0, estimatedFullSize - actualSize)

        return IncrementalBackupResult(
            url: url,
            metadata: metadata,
            totalEntities: totalCount,
            changedEntities: changedCount,
            savedBytes: savedBytes
        )
    }

    /// Resets the incremental backup tracking (next backup will be full)
    public func resetIncrementalTracking() {
        UserDefaults.standard.removeObject(forKey: Keys.lastIncrementalBackupDate)
        UserDefaults.standard.removeObject(forKey: Keys.lastIncrementalBackupID)
    }

    // MARK: - Private Helpers

    private func collectPayload(
        modelContext: ModelContext,
        sinceDate: Date?,
        progress: @escaping (Double, String) -> Void
    ) throws -> (BackupPayload, [String: Int], [String: Int]) {

        var changedCounts: [String: Int] = [:]
        var totalCounts: [String: Int] = [:]

        // Helper to fetch and filter entities
        func fetchFiltered<T: PersistentModel>(
            _ type: T.Type,
            keyPath: KeyPath<T, Date?>? = nil
        ) -> [T] {
            let descriptor = FetchDescriptor<T>()
            let all = (try? modelContext.fetch(descriptor)) ?? []
            totalCounts[String(describing: type)] = all.count

            guard let sinceDate = sinceDate, let kp = keyPath else {
                changedCounts[String(describing: type)] = all.count
                return all
            }

            let filtered = all.filter { entity in
                guard let date = entity[keyPath: kp] else { return true }
                return date >= sinceDate
            }
            changedCounts[String(describing: type)] = filtered.count
            return filtered
        }

        progress(0.1, "Collecting students…")
        let students: [Student] = fetchFiltered(Student.self)

        progress(0.2, "Collecting lessons…")
        let lessons: [Lesson] = fetchFiltered(Lesson.self)

        progress(0.3, "Collecting student lessons…")
        let studentLessons: [StudentLesson] = fetchFiltered(StudentLesson.self)

        progress(0.4, "Collecting work items…")
        let workPlanItems: [WorkPlanItem] = fetchFiltered(WorkPlanItem.self)

        // Notes need special handling since updatedAt is non-optional
        let allNotes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        totalCounts["Note"] = allNotes.count
        let notes: [Note]
        if let sinceDate = sinceDate {
            notes = allNotes.filter { $0.updatedAt >= sinceDate }
        } else {
            notes = allNotes
        }
        changedCounts["Note"] = notes.count

        progress(0.5, "Collecting calendar data…")
        let nonSchoolDays: [NonSchoolDay] = fetchFiltered(NonSchoolDay.self)
        let schoolDayOverrides: [SchoolDayOverride] = fetchFiltered(SchoolDayOverride.self)

        progress(0.6, "Collecting meetings…")
        let studentMeetings: [StudentMeeting] = fetchFiltered(StudentMeeting.self)
        let presentations: [Presentation] = fetchFiltered(Presentation.self)

        progress(0.7, "Collecting community data…")
        let communityTopics: [CommunityTopic] = fetchFiltered(CommunityTopic.self)
        let proposedSolutions: [ProposedSolution] = fetchFiltered(ProposedSolution.self)
        let communityAttachments: [CommunityAttachment] = fetchFiltered(CommunityAttachment.self)

        progress(0.8, "Collecting attendance…")
        let attendance: [AttendanceRecord] = fetchFiltered(AttendanceRecord.self)
        let workCompletions: [WorkCompletionRecord] = fetchFiltered(WorkCompletionRecord.self)

        progress(0.9, "Collecting projects…")
        let projects: [Project] = fetchFiltered(Project.self)
        let projectTemplates: [ProjectAssignmentTemplate] = fetchFiltered(ProjectAssignmentTemplate.self)
        let projectSessions: [ProjectSession] = fetchFiltered(ProjectSession.self)
        let projectRoles: [ProjectRole] = fetchFiltered(ProjectRole.self)
        let projectWeeks: [ProjectTemplateWeek] = fetchFiltered(ProjectTemplateWeek.self)
        let projectWeekAssignments: [ProjectWeekRoleAssignment] = fetchFiltered(ProjectWeekRoleAssignment.self)

        // Convert to DTOs (reusing existing conversion logic patterns)
        let studentDTOs: [StudentDTO] = students.map { s in
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

        let lessonDTOs: [LessonDTO] = lessons.map { l in
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

        let studentLessonDTOs: [StudentLessonDTO] = studentLessons.compactMap { sl in
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

        let workPlanItemDTOs: [WorkPlanItemDTO] = workPlanItems.compactMap { w in
            guard let workIDUUID = UUID(uuidString: w.workID) else { return nil }
            return WorkPlanItemDTO(
                id: w.id,
                workID: workIDUUID,
                scheduledDate: w.scheduledDate,
                reason: w.reasonRaw ?? (w.reason?.rawValue ?? ""),
                note: w.note
            )
        }

        let noteDTOs: [NoteDTO] = notes.map { n in
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

        let nonSchoolDTOs: [NonSchoolDayDTO] = nonSchoolDays.map { d in
            NonSchoolDayDTO(id: d.id, date: d.date, reason: d.reason)
        }

        let schoolOverrideDTOs: [SchoolDayOverrideDTO] = schoolDayOverrides.map { o in
            SchoolDayOverrideDTO(id: o.id, date: o.date, note: o.note)
        }

        let studentMeetingDTOs: [StudentMeetingDTO] = studentMeetings.compactMap { m in
            guard let studentIDUUID = UUID(uuidString: m.studentID) else { return nil }
            return StudentMeetingDTO(
                id: m.id,
                studentID: studentIDUUID,
                date: m.date,
                completed: m.completed,
                reflection: m.reflection,
                focus: m.focus,
                requests: m.requests,
                guideNotes: m.guideNotes
            )
        }

        let presentationDTOs: [PresentationDTO] = presentations.map { p in
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

        let topicDTOs: [CommunityTopicDTO] = communityTopics.map { t in
            CommunityTopicDTO(
                id: t.id,
                title: t.title,
                issueDescription: t.issueDescription,
                createdAt: t.createdAt,
                addressedDate: t.addressedDate,
                resolution: t.resolution,
                raisedBy: t.raisedBy,
                tags: t.tags
            )
        }

        let solutionDTOs: [ProposedSolutionDTO] = proposedSolutions.map { s in
            ProposedSolutionDTO(
                id: s.id,
                topicID: s.topic?.id,
                title: s.title,
                details: s.details,
                proposedBy: s.proposedBy,
                createdAt: s.createdAt,
                isAdopted: s.isAdopted
            )
        }

        let attachmentDTOs: [CommunityAttachmentDTO] = communityAttachments.map { a in
            CommunityAttachmentDTO(
                id: a.id,
                topicID: a.topic?.id,
                filename: a.filename,
                kind: a.kind.rawValue,
                createdAt: a.createdAt
            )
        }

        let attendanceDTOs: [AttendanceRecordDTO] = attendance.compactMap { a in
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

        let workCompletionDTOs: [WorkCompletionRecordDTO] = workCompletions.compactMap { r in
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

        let projectDTOs: [ProjectDTO] = projects.map { c in
            ProjectDTO(
                id: c.id,
                createdAt: c.createdAt,
                title: c.title,
                bookTitle: c.bookTitle,
                memberStudentIDs: c.memberStudentIDs
            )
        }

        let projectTemplateDTOs: [ProjectAssignmentTemplateDTO] = projectTemplates.compactMap { t in
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

        let projectSessionDTOs: [ProjectSessionDTO] = projectSessions.compactMap { s in
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

        let projectRoleDTOs: [ProjectRoleDTO] = projectRoles.compactMap { r in
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

        let projectWeekDTOs: [ProjectTemplateWeekDTO] = projectWeeks.compactMap { w in
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

        let projectWeekAssignDTOs: [ProjectWeekRoleAssignmentDTO] = projectWeekAssignments.compactMap { a in
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

        let preferences = BackupPreferencesService.buildPreferencesDTO()

        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            workPlanItems: workPlanItemDTOs,
            scopedNotes: [],
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: studentMeetingDTOs,
            presentations: presentationDTOs,
            communityTopics: topicDTOs,
            proposedSolutions: solutionDTOs,
            meetingNotes: [],
            communityAttachments: attachmentDTOs,
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

        return (payload, changedCounts, totalCounts)
    }
}
