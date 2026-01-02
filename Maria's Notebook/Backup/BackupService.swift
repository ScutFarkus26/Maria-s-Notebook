import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import Compression

@MainActor
public final class BackupService {
    public enum RestoreMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case merge
        case replace
        public var id: String { rawValue }
    }

    public init() {}
    
    // MARK: - Size Estimation
    
    /// Estimates the backup size in bytes based on current entity counts.
    /// This performs lightweight fetches to count entities (doesn't process full data).
    /// - Parameter modelContext: The model context to count entities from
    /// - Returns: Estimated backup size in bytes (approximate, accounts for compression)
    public func estimateBackupSize(modelContext: ModelContext) -> Int64 {
        // Count entities by fetching them (SwiftData doesn't have a count-only API)
        // This is relatively fast since we're just counting, not processing data
        var counts: [String: Int] = [:]
        counts["Student"] = safeFetch(Student.self, using: modelContext).count
        counts["Lesson"] = safeFetch(Lesson.self, using: modelContext).count
        counts["StudentLesson"] = safeFetch(StudentLesson.self, using: modelContext).count
        counts["WorkContract"] = safeFetch(WorkContract.self, using: modelContext).count
        counts["WorkPlanItem"] = safeFetch(WorkPlanItem.self, using: modelContext).count
        counts["ScopedNote"] = safeFetch(ScopedNote.self, using: modelContext).count
        counts["Note"] = safeFetch(Note.self, using: modelContext).count
        counts["NonSchoolDay"] = safeFetch(NonSchoolDay.self, using: modelContext).count
        counts["SchoolDayOverride"] = safeFetch(SchoolDayOverride.self, using: modelContext).count
        counts["StudentMeeting"] = safeFetch(StudentMeeting.self, using: modelContext).count
        counts["Presentation"] = safeFetch(Presentation.self, using: modelContext).count
        counts["CommunityTopic"] = safeFetch(CommunityTopic.self, using: modelContext).count
        counts["ProposedSolution"] = safeFetch(ProposedSolution.self, using: modelContext).count
        counts["MeetingNote"] = safeFetch(MeetingNote.self, using: modelContext).count
        counts["CommunityAttachment"] = safeFetch(CommunityAttachment.self, using: modelContext).count
        counts["AttendanceRecord"] = safeFetch(AttendanceRecord.self, using: modelContext).count
        counts["WorkCompletionRecord"] = safeFetch(WorkCompletionRecord.self, using: modelContext).count
        counts["Project"] = safeFetch(Project.self, using: modelContext).count
        counts["ProjectAssignmentTemplate"] = safeFetch(ProjectAssignmentTemplate.self, using: modelContext).count
        counts["ProjectSession"] = safeFetch(ProjectSession.self, using: modelContext).count
        counts["ProjectRole"] = safeFetch(ProjectRole.self, using: modelContext).count
        counts["ProjectTemplateWeek"] = safeFetch(ProjectTemplateWeek.self, using: modelContext).count
        counts["ProjectWeekRoleAssignment"] = safeFetch(ProjectWeekRoleAssignment.self, using: modelContext).count
        
        return estimateBackupSizeFromCounts(counts)
    }
    
    /// Estimates backup size from entity counts dictionary.
    /// Uses average sizes per entity type and accounts for compression.
    public func estimateBackupSizeFromCounts(_ counts: [String: Int]) -> Int64 {
        // Average bytes per entity type (based on typical JSON size)
        // These are rough estimates for uncompressed JSON
        let averageBytesPerEntity: [String: Int] = [
            "Student": 600,
            "Lesson": 2500,
            "StudentLesson": 300,
            "WorkContract": 800,
            "WorkPlanItem": 500,
            "ScopedNote": 400,
            "Note": 300,
            "NonSchoolDay": 200,
            "SchoolDayOverride": 200,
            "StudentMeeting": 1200,
            "Presentation": 800,
            "CommunityTopic": 1500,
            "ProposedSolution": 1000,
            "MeetingNote": 800,
            "CommunityAttachment": 600,
            "AttendanceRecord": 300,
            "WorkCompletionRecord": 400,
            "Project": 2000,
            "ProjectAssignmentTemplate": 2500,
            "ProjectSession": 1500,
            "ProjectRole": 1200,
            "ProjectTemplateWeek": 1800,
            "ProjectWeekRoleAssignment": 300
        ]
        
        // Calculate uncompressed size
        let uncompressedSize = counts.reduce(0) { total, pair in
            let averageSize = averageBytesPerEntity[pair.key] ?? 1000 // Default to 1KB if unknown
            return total + (averageSize * pair.value)
        }
        
        // Add envelope overhead (metadata, manifest, etc.) - roughly 2KB
        let envelopeOverhead: Int64 = 2048
        
        // Account for compression (LZFSE typically achieves 2-4x compression)
        // Use 3x compression ratio as average estimate
        let compressionRatio = 3.0
        let compressedSize = Int64(Double(uncompressedSize) / compressionRatio)
        
        return compressedSize + envelopeOverhead
    }

    // MARK: - Export
    public func exportBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        // 1. Handle Security Scope (Vital for macOS Bookmarks)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.0), "Collecting students…")

        // Fetch entities using batch processing for large datasets to reduce memory pressure
        // Batch size of 1000 provides a good balance between memory efficiency and performance
        let students: [Student] = safeFetchInBatches(Student.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.06), "Collecting lessons…")
        let lessons: [Lesson] = safeFetchInBatches(Lesson.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.12), "Collecting student lessons…")
        // Use batch fetching for StudentLesson (may have corrupted studentIDs data, handled in safeFetchWithErrorHandling)
        let studentLessons: [StudentLesson] = safeFetchInBatchesWithErrorHandling(StudentLesson.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.18), "Collecting work contracts…")
        let workContracts: [WorkContract] = safeFetchInBatches(WorkContract.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.21), "Collecting work plan items…")
        let workPlanItems: [WorkPlanItem] = safeFetchInBatches(WorkPlanItem.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.24), "Collecting notes…")
        let scopedNotes: [ScopedNote] = safeFetchInBatches(ScopedNote.self, using: modelContext)
        let notes: [Note] = safeFetchInBatches(Note.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.27), "Collecting calendar data…")
        let nonSchoolDays: [NonSchoolDay] = safeFetchInBatches(NonSchoolDay.self, using: modelContext)
        let schoolDayOverrides: [SchoolDayOverride] = safeFetchInBatches(SchoolDayOverride.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.30), "Collecting meetings and presentations…")
        let studentMeetings: [StudentMeeting] = safeFetchInBatches(StudentMeeting.self, using: modelContext)
        let presentations: [Presentation] = safeFetchInBatches(Presentation.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.33), "Collecting community data…")
        // Use batch fetching with error handling for CommunityTopic (may have corrupted data)
        let communityTopics: [CommunityTopic] = safeFetchInBatchesWithErrorHandling(CommunityTopic.self, using: modelContext)
        let proposedSolutions: [ProposedSolution] = safeFetchInBatches(ProposedSolution.self, using: modelContext)
        let meetingNotes: [MeetingNote] = safeFetchInBatches(MeetingNote.self, using: modelContext)
        let communityAttachments: [CommunityAttachment] = safeFetchInBatches(CommunityAttachment.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.36), "Collecting attendance and work completions…")
        let attendance: [AttendanceRecord] = safeFetchInBatches(AttendanceRecord.self, using: modelContext)
        let workCompletions: [WorkCompletionRecord] = safeFetchInBatches(WorkCompletionRecord.self, using: modelContext)
        progress(BackupProgress.progress(for: .collecting, subProgress: 0.39), "Collecting projects…")
        let projects: [Project] = safeFetchInBatches(Project.self, using: modelContext)
        let projectTemplates: [ProjectAssignmentTemplate] = safeFetchInBatches(ProjectAssignmentTemplate.self, using: modelContext)
        let projectSessions: [ProjectSession] = safeFetchInBatches(ProjectSession.self, using: modelContext)
        let projectRoles: [ProjectRole] = safeFetchInBatches(ProjectRole.self, using: modelContext)
        let projectWeeks: [ProjectTemplateWeek] = safeFetchInBatches(ProjectTemplateWeek.self, using: modelContext)
        let projectWeekAssignments: [ProjectWeekRoleAssignment] = safeFetchInBatches(ProjectWeekRoleAssignment.self, using: modelContext)

        // Map to DTOs
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
            // CloudKit compatibility: Convert String lessonID to UUID for DTO
            guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else {
                return nil // Skip if lessonID is invalid
            }
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

        let workContractDTOs: [WorkContractDTO] = workContracts.map { c in
            WorkContractDTO(
                id: c.id,
                studentID: c.studentID,
                lessonID: c.lessonID,
                presentationID: c.presentationID,
                status: c.statusRaw,
                scheduledDate: c.scheduledDate,
                createdAt: c.createdAt,
                completedAt: c.completedAt,
                kind: c.kindRaw,
                scheduledReason: c.scheduledReasonRaw,
                scheduledNote: c.scheduledNote,
                completionOutcome: c.completionOutcome?.rawValue,
                completionNote: c.completionNote,
                legacyStudentLessonID: c.legacyStudentLessonID
            )
        }

        let workPlanItemDTOs: [WorkPlanItemDTO] = workPlanItems.compactMap { w in
            // CloudKit compatibility: Convert String workID to UUID for DTO
            guard let workIDUUID = UUID(uuidString: w.workID) else { return nil }
            return WorkPlanItemDTO(
                id: w.id,
                workID: workIDUUID,
                scheduledDate: w.scheduledDate,
                reason: w.reasonRaw ?? (w.reason?.rawValue ?? ""),
                note: w.note
            )
        }

        let scopedNoteDTOs: [ScopedNoteDTO] = scopedNotes.map { n in
            ScopedNoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                scope: String(data: n.scopeRaw, encoding: .utf8) ?? "{}",
                legacyFingerprint: n.legacyFingerprint,
                studentLessonID: n.studentLesson?.id,
                workID: n.workContractID.flatMap { UUID(uuidString: $0) },
                presentationID: n.presentationID.flatMap { UUID(uuidString: $0) },
                workContractID: n.workContractID.flatMap { UUID(uuidString: $0) }
            )
        }

        let noteDTOs: [NoteDTO] = notes.map { n in
            // Manually encode scope since scopeBlob is private/internal
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
            // CloudKit compatibility: Convert String studentID to UUID for DTO
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

        let meetingNoteDTOs: [MeetingNoteDTO] = meetingNotes.map { n in
            MeetingNoteDTO(
                id: n.id,
                topicID: n.topic?.id,
                speaker: n.speaker,
                content: n.content,
                createdAt: n.createdAt
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

        // Attendance & Work Completions
        let attendanceDTOs: [AttendanceRecordDTO] = attendance.compactMap { a in
            // CloudKit compatibility: Convert String studentID to UUID for DTO
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
            // CloudKit compatibility: Convert String IDs to UUIDs for DTO
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

        // Projects
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
            // CloudKit compatibility: Convert String projectID to UUID for DTO
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
            // CloudKit compatibility: Convert String IDs to UUIDs for DTO
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
            // CloudKit compatibility: Convert String projectID to UUID for DTO
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
            // CloudKit compatibility: Convert String projectID to UUID for DTO
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
            // CloudKit compatibility: Convert String IDs to UUIDs for DTO
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

        // Preferences
        let preferences = buildPreferencesDTO()

        // Build payload
        let payload = BackupPayload(
            items: [],
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: studentLessonDTOs,
            workContracts: workContractDTOs,
            workPlanItems: workPlanItemDTOs,
            scopedNotes: scopedNoteDTOs,
            notes: noteDTOs,
            nonSchoolDays: nonSchoolDTOs,
            schoolDayOverrides: schoolOverrideDTOs,
            studentMeetings: studentMeetingDTOs,
            presentations: presentationDTOs,
            communityTopics: topicDTOs,
            proposedSolutions: solutionDTOs,
            meetingNotes: meetingNoteDTOs,
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

        progress(BackupProgress.progress(for: .encoding), "Encoding data…")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys  // Ensures deterministic JSON for checksum validation
        let payloadBytes = try encoder.encode(payload)
        let sha = sha256Hex(payloadBytes)  // Checksum of uncompressed data for integrity

        // Compression (for format version 6+)
        progress(BackupProgress.progress(for: .encoding), "Compressing data…")
        let compressedPayloadBytes = try compressData(payloadBytes)
        
        // Encryption and storage
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?
        let compressionUsed: String?

        if let password = password, !password.isEmpty {
            progress(BackupProgress.progress(for: .encrypting), "Encrypting data…")
            // 1. Generate 32-byte Salt
            let saltKey = SymmetricKey(size: .bits256)
            let salt = saltKey.withUnsafeBytes { Data($0) }
            
            // 2. Derive Key
            let key = deriveKey(password: password, salt: salt)
            
            // 3. Seal compressed data
            let sealedBox = try AES.GCM.seal(compressedPayloadBytes, using: key)
            guard let combined = sealedBox.combined else {
                throw NSError(domain: "BackupService", code: 1100, userInfo: [NSLocalizedDescriptionKey: "Encryption failed (could not combine data)."])
            }
            
            // 4. Prepend salt to ciphertext so we can retrieve it during import
            finalEncrypted = salt + combined
            finalPayload = nil
            finalCompressed = nil
            compressionUsed = BackupFile.compressionAlgorithm
        } else {
            // Unencrypted: store compressed data
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
            compressionUsed = BackupFile.compressionAlgorithm
        }

        // Manifest counts
        let counts: [String: Int] = [
            "Student": studentDTOs.count,
            "Lesson": lessonDTOs.count,
            "StudentLesson": studentLessonDTOs.count,
            "WorkContract": workContractDTOs.count,
            "WorkPlanItem": workPlanItemDTOs.count,
            "ScopedNote": scopedNoteDTOs.count,
            "Note": noteDTOs.count,
            "NonSchoolDay": nonSchoolDTOs.count,
            "SchoolDayOverride": schoolOverrideDTOs.count,
            "StudentMeeting": studentMeetingDTOs.count,
            "Presentation": presentationDTOs.count,
            "CommunityTopic": topicDTOs.count,
            "ProposedSolution": solutionDTOs.count,
            "MeetingNote": meetingNoteDTOs.count,
            "CommunityAttachment": attachmentDTOs.count,
            "AttendanceRecord": attendanceDTOs.count,
            "WorkCompletionRecord": workCompletionDTOs.count,
            "Project": projectDTOs.count,
            "ProjectAssignmentTemplate": projectTemplateDTOs.count,
            "ProjectSession": projectSessionDTOs.count,
            "ProjectRole": projectRoleDTOs.count,
            "ProjectTemplateWeek": projectWeekDTOs.count,
            "ProjectWeekRoleAssignment": projectWeekAssignDTOs.count
        ]

        // Envelope
        let env = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(entityCounts: counts, sha256: sha, notes: nil, compression: compressionUsed),
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed
        )

        progress(BackupProgress.progress(for: .writing), "Writing backup file…")
        let envBytes = try encoder.encode(env)
        
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)
        
        // Set appropriate file permissions (read-write for owner only if encrypted, otherwise standard)
        if finalEncrypted != nil {
            try? FileManager.default.setAttributes([
                .posixPermissions: NSNumber(value: 0o600)  // rw-------
            ], ofItemAtPath: url.path)
        }

        // Verify backup by reading it back
        progress(BackupProgress.progress(for: .verifying), "Verifying backup…")
        let verificationData = try Data(contentsOf: url)
        let verificationDecoder = JSONDecoder()
        verificationDecoder.dateDecodingStrategy = .iso8601
        let _ = try verificationDecoder.decode(BackupEnvelope.self, from: verificationData)
        // If decode succeeds, file structure is valid

        progress(BackupProgress.progress(for: .complete), "Backup complete")
        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: (finalEncrypted != nil),
            createdAt: Date(),
            entityCounts: counts,
            warnings: [
                "Imported documents and file attachments are not included in backups by design."
            ]
        )
    }

    // MARK: - Restore Preview
    public func previewImport(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> RestorePreview {
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading file…")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        // Resolve payload bytes
        let payloadBytes: Data
        let isCompressed = envelope.manifest.compression != nil
        
        if envelope.payload != nil {
            // Uncompressed unencrypted backup (format version < 6)
            if let extracted = try extractPayloadBytes(from: data) {
                payloadBytes = extracted
            } else {
                // Fallback: re-encode if extraction fails
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .sortedKeys
                payloadBytes = try encoder.encode(envelope.payload!)
            }
        } else if let compressed = envelope.compressedPayload {
            // Compressed but unencrypted backup (format version 6+)
            progress(0.15, "Decompressing data…")
            payloadBytes = try decompressData(compressed)
        } else if let enc = envelope.encryptedPayload {
            // Encrypted backup (may also be compressed)
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."])
            }
            
            // Extract Salt (first 32 bytes)
            guard enc.count > 32 else {
                throw NSError(domain: "BackupService", code: 1104, userInfo: [NSLocalizedDescriptionKey: "Corrupted encrypted data (too short)."])
            }
            let salt = enc.prefix(32)
            let ciphertext = enc.dropFirst(32)
            
            // Derive Key
            let key = deriveKey(password: password, salt: Data(salt))
            
            // Open Box
            progress(0.15, "Decrypting data…")
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedBytes = try AES.GCM.open(sealedBox, using: key)
            
            // Decompress if compressed
            if isCompressed {
                progress(0.17, "Decompressing data…")
                payloadBytes = try decompressData(decryptedBytes)
            } else {
                payloadBytes = decryptedBytes
            }
            
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating checksum…")
        // Checksum validation: enforced for format version 5+, optional bypass for older versions
        let isNewFormat = envelope.formatVersion >= BackupFile.checksumEnforcedVersion
        let bypassEnabled = UserDefaults.standard.bool(forKey: "Backup.allowChecksumBypass")
        let shouldValidateChecksum = isNewFormat || !bypassEnabled
        
        if shouldValidateChecksum && !envelope.manifest.sha256.isEmpty {
            let sha = sha256Hex(payloadBytes)
            guard sha == envelope.manifest.sha256 else {
                throw NSError(
                    domain: "BackupService",
                    code: 1102,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Checksum mismatch. The backup file may be corrupted. Expected: \(envelope.manifest.sha256.prefix(16))..., got: \(sha.prefix(16))..."
                    ]
                )
            }
        }

        // Decode payload
        let payload = try decoder.decode(BackupPayload.self, from: payloadBytes)

        progress(0.50, "Analyzing…")
        func count<T: PersistentModel>(_ type: T.Type) -> Int { ((try? modelContext.fetch(FetchDescriptor<T>())) ?? []).count }
        func exists<T: PersistentModel>(_ type: T.Type, _ id: UUID) -> Bool { ((try? fetchOne(type, id: id, using: modelContext)) ?? nil) != nil }

        var inserts: [String: Int] = [:]
        var skips: [String: Int] = [:]
        var deletes: [String: Int] = [:]
        var warnings: [String] = []

        // Helper to assign counts
        func assign(_ key: String, ins: Int, sk: Int = 0, del: Int = 0) {
            inserts[key] = ins
            skips[key] = sk
            deletes[key] = del
        }

        if mode == .replace {
            // All current data will be deleted, and payload inserted
            assign("Student", ins: payload.students.count, del: count(Student.self))
            assign("Lesson", ins: payload.lessons.count, del: count(Lesson.self))
            assign("StudentLesson", ins: payload.studentLessons.count, del: count(StudentLesson.self))
            assign("WorkContract", ins: payload.workContracts.count, del: count(WorkContract.self))
            assign("WorkPlanItem", ins: payload.workPlanItems.count, del: count(WorkPlanItem.self))
            assign("ScopedNote", ins: payload.scopedNotes.count, del: count(ScopedNote.self))
            assign("Note", ins: payload.notes.count, del: count(Note.self))
            assign("NonSchoolDay", ins: payload.nonSchoolDays.count, del: count(NonSchoolDay.self))
            assign("SchoolDayOverride", ins: payload.schoolDayOverrides.count, del: count(SchoolDayOverride.self))
            assign("StudentMeeting", ins: payload.studentMeetings.count, del: count(StudentMeeting.self))
            assign("Presentation", ins: payload.presentations.count, del: count(Presentation.self))
            assign("CommunityTopic", ins: payload.communityTopics.count, del: count(CommunityTopic.self))
            assign("ProposedSolution", ins: payload.proposedSolutions.count, del: count(ProposedSolution.self))
            assign("MeetingNote", ins: payload.meetingNotes.count, del: count(MeetingNote.self))
            assign("CommunityAttachment", ins: payload.communityAttachments.count, del: count(CommunityAttachment.self))
            assign("AttendanceRecord", ins: payload.attendance.count, del: count(AttendanceRecord.self))
            assign("WorkCompletionRecord", ins: payload.workCompletions.count, del: count(WorkCompletionRecord.self))
            assign("Project", ins: payload.projects.count, del: count(Project.self))
            assign("ProjectAssignmentTemplate", ins: payload.projectAssignmentTemplates.count, del: count(ProjectAssignmentTemplate.self))
            assign("ProjectSession", ins: payload.projectSessions.count, del: count(ProjectSession.self))
            assign("ProjectRole", ins: payload.projectRoles.count, del: count(ProjectRole.self))
            assign("ProjectTemplateWeek", ins: payload.projectTemplateWeeks.count, del: count(ProjectTemplateWeek.self))
            assign("ProjectWeekRoleAssignment", ins: payload.projectWeekRoleAssignments.count, del: count(ProjectWeekRoleAssignment.self))
        } else {
            // Merge: compute inserts vs. skips
            assign("Student", ins: payload.students.filter { !exists(Student.self, $0.id) }.count, sk: payload.students.filter { exists(Student.self, $0.id) }.count)
            assign("Lesson", ins: payload.lessons.filter { !exists(Lesson.self, $0.id) }.count, sk: payload.lessons.filter { exists(Lesson.self, $0.id) }.count)

            let lessonsInStore = Set(((try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []).map { $0.id })
            let lessonsInPayload = Set(payload.lessons.map { $0.id })
            let studentLessonAnalysis = payload.studentLessons.reduce(into: (ins: 0, sk: 0, missingLesson: 0)) { acc, sl in
                // DTO has lessonID as UUID, so use it directly for comparison
                let hasLesson = lessonsInStore.contains(sl.lessonID) || lessonsInPayload.contains(sl.lessonID)
                if !hasLesson {
                    acc.sk += 1
                    acc.missingLesson += 1
                } else if exists(StudentLesson.self, sl.id) {
                    acc.sk += 1
                } else {
                    acc.ins += 1
                }
            }
            assign("StudentLesson", ins: studentLessonAnalysis.ins, sk: studentLessonAnalysis.sk)
            if studentLessonAnalysis.missingLesson > 0 {
                warnings.append("\(studentLessonAnalysis.missingLesson) StudentLesson records reference missing Lessons and will be skipped.")
            }

            assign("WorkContract", ins: payload.workContracts.filter { !exists(WorkContract.self, $0.id) }.count, sk: payload.workContracts.filter { exists(WorkContract.self, $0.id) }.count)
            assign("WorkPlanItem", ins: payload.workPlanItems.filter { !exists(WorkPlanItem.self, $0.id) }.count, sk: payload.workPlanItems.filter { exists(WorkPlanItem.self, $0.id) }.count)
            assign("ScopedNote", ins: payload.scopedNotes.filter { !exists(ScopedNote.self, $0.id) }.count, sk: payload.scopedNotes.filter { exists(ScopedNote.self, $0.id) }.count)
            assign("Note", ins: payload.notes.filter { !exists(Note.self, $0.id) }.count, sk: payload.notes.filter { exists(Note.self, $0.id) }.count)
            assign("NonSchoolDay", ins: payload.nonSchoolDays.filter { !exists(NonSchoolDay.self, $0.id) }.count, sk: payload.nonSchoolDays.filter { exists(NonSchoolDay.self, $0.id) }.count)
            assign("SchoolDayOverride", ins: payload.schoolDayOverrides.filter { !exists(SchoolDayOverride.self, $0.id) }.count, sk: payload.schoolDayOverrides.filter { exists(SchoolDayOverride.self, $0.id) }.count)
            assign("StudentMeeting", ins: payload.studentMeetings.filter { !exists(StudentMeeting.self, $0.id) }.count, sk: payload.studentMeetings.filter { exists(StudentMeeting.self, $0.id) }.count)
            assign("Presentation", ins: payload.presentations.filter { !exists(Presentation.self, $0.id) }.count, sk: payload.presentations.filter { exists(Presentation.self, $0.id) }.count)
            assign("CommunityTopic", ins: payload.communityTopics.filter { !exists(CommunityTopic.self, $0.id) }.count, sk: payload.communityTopics.filter { exists(CommunityTopic.self, $0.id) }.count)
            assign("ProposedSolution", ins: payload.proposedSolutions.filter { !exists(ProposedSolution.self, $0.id) }.count, sk: payload.proposedSolutions.filter { exists(ProposedSolution.self, $0.id) }.count)
            assign("MeetingNote", ins: payload.meetingNotes.filter { !exists(MeetingNote.self, $0.id) }.count, sk: payload.meetingNotes.filter { exists(MeetingNote.self, $0.id) }.count)
            assign("CommunityAttachment", ins: payload.communityAttachments.filter { !exists(CommunityAttachment.self, $0.id) }.count, sk: payload.communityAttachments.filter { exists(CommunityAttachment.self, $0.id) }.count)
            assign("AttendanceRecord", ins: payload.attendance.filter { !exists(AttendanceRecord.self, $0.id) }.count, sk: payload.attendance.filter { exists(AttendanceRecord.self, $0.id) }.count)
            assign("WorkCompletionRecord", ins: payload.workCompletions.filter { !exists(WorkCompletionRecord.self, $0.id) }.count, sk: payload.workCompletions.filter { exists(WorkCompletionRecord.self, $0.id) }.count)
            assign("Project", ins: payload.projects.filter { !exists(Project.self, $0.id) }.count, sk: payload.projects.filter { exists(Project.self, $0.id) }.count)
            assign("ProjectAssignmentTemplate", ins: payload.projectAssignmentTemplates.filter { !exists(ProjectAssignmentTemplate.self, $0.id) }.count, sk: payload.projectAssignmentTemplates.filter { exists(ProjectAssignmentTemplate.self, $0.id) }.count)
            assign("ProjectSession", ins: payload.projectSessions.filter { !exists(ProjectSession.self, $0.id) }.count, sk: payload.projectSessions.filter { exists(ProjectSession.self, $0.id) }.count)
            assign("ProjectRole", ins: payload.projectRoles.filter { !exists(ProjectRole.self, $0.id) }.count, sk: payload.projectRoles.filter { exists(ProjectRole.self, $0.id) }.count)
            assign("ProjectTemplateWeek", ins: payload.projectTemplateWeeks.filter { !exists(ProjectTemplateWeek.self, $0.id) }.count, sk: payload.projectTemplateWeeks.filter { exists(ProjectTemplateWeek.self, $0.id) }.count)
            assign("ProjectWeekRoleAssignment", ins: payload.projectWeekRoleAssignments.filter { !exists(ProjectWeekRoleAssignment.self, $0.id) }.count, sk: payload.projectWeekRoleAssignments.filter { exists(ProjectWeekRoleAssignment.self, $0.id) }.count)
        }

        let totalInserts = inserts.values.reduce(0, +)
        let totalDeletes = deletes.values.reduce(0, +)

        progress(1.0, "Done")
        return RestorePreview(
            mode: mode.rawValue,
            entityInserts: inserts,
            entitySkips: skips,
            entityDeletes: deletes,
            totalInserts: totalInserts,
            totalDeletes: totalDeletes,
            warnings: warnings
        )
    }

    // MARK: - Import
    public func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        progress(0.05, "Reading file…")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        // Resolve payload bytes
        let payloadBytes: Data
        let isCompressed = envelope.manifest.compression != nil
        
        if envelope.payload != nil {
            // Uncompressed unencrypted backup (format version < 6)
            if let extracted = try extractPayloadBytes(from: data) {
                payloadBytes = extracted
            } else {
                // Fallback: re-encode if extraction fails
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .sortedKeys
                payloadBytes = try encoder.encode(envelope.payload!)
            }
        } else if let compressed = envelope.compressedPayload {
            // Compressed but unencrypted backup (format version 6+)
            progress(0.15, "Decompressing data…")
            payloadBytes = try decompressData(compressed)
        } else if let enc = envelope.encryptedPayload {
            // Encrypted backup (may also be compressed)
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."])
            }
            guard enc.count > 32 else {
                throw NSError(domain: "BackupService", code: 1104, userInfo: [NSLocalizedDescriptionKey: "Corrupted encrypted data."])
            }
            
            let salt = enc.prefix(32)
            let ciphertext = enc.dropFirst(32)
            let key = deriveKey(password: password, salt: Data(salt))
            
            progress(0.15, "Decrypting data…")
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedBytes = try AES.GCM.open(sealedBox, using: key)
            
            // Decompress if compressed
            if isCompressed {
                progress(0.17, "Decompressing data…")
                payloadBytes = try decompressData(decryptedBytes)
            } else {
                payloadBytes = decryptedBytes
            }
            
        } else {
            throw NSError(domain: "BackupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating checksum…")
        // Checksum validation: enforced for format version 5+, optional bypass for older versions
        let isNewFormat = envelope.formatVersion >= BackupFile.checksumEnforcedVersion
        let bypassEnabled = UserDefaults.standard.bool(forKey: "Backup.allowChecksumBypass")
        let shouldValidateChecksum = isNewFormat || !bypassEnabled
        
        if shouldValidateChecksum && !envelope.manifest.sha256.isEmpty {
            let sha = sha256Hex(payloadBytes)
            guard sha == envelope.manifest.sha256 else {
                throw NSError(
                    domain: "BackupService",
                    code: 1002,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Checksum mismatch. The backup file may be corrupted. Expected: \(envelope.manifest.sha256.prefix(16))..., got: \(sha.prefix(16))..."
                    ]
                )
            }
        }

        // Decode payload
        let payload = try decoder.decode(BackupPayload.self, from: payloadBytes)

        // Validation: duplicate IDs for all entity types
        var duplicateErrors: [String] = []
        
        func validateNoDuplicates(_ ids: [UUID], entityName: String) {
            let uniqueIds = Set(ids)
            if ids.count != uniqueIds.count {
                let duplicates = Array(Set(ids.filter { id in ids.filter { $0 == id }.count > 1 }))
                let duplicateStrings = duplicates.prefix(5).map { $0.uuidString }
                duplicateErrors.append("\(entityName): \(duplicates.count) duplicate ID(s) found (showing first 5: \(duplicateStrings.joined(separator: ", ")))")
            }
        }
        
        validateNoDuplicates(payload.students.map { $0.id }, entityName: "Student")
        validateNoDuplicates(payload.lessons.map { $0.id }, entityName: "Lesson")
        validateNoDuplicates(payload.studentLessons.map { $0.id }, entityName: "StudentLesson")
        validateNoDuplicates(payload.workContracts.map { $0.id }, entityName: "WorkContract")
        validateNoDuplicates(payload.workPlanItems.map { $0.id }, entityName: "WorkPlanItem")
        validateNoDuplicates(payload.scopedNotes.map { $0.id }, entityName: "ScopedNote")
        validateNoDuplicates(payload.notes.map { $0.id }, entityName: "Note")
        validateNoDuplicates(payload.nonSchoolDays.map { $0.id }, entityName: "NonSchoolDay")
        validateNoDuplicates(payload.schoolDayOverrides.map { $0.id }, entityName: "SchoolDayOverride")
        validateNoDuplicates(payload.studentMeetings.map { $0.id }, entityName: "StudentMeeting")
        validateNoDuplicates(payload.presentations.map { $0.id }, entityName: "Presentation")
        validateNoDuplicates(payload.communityTopics.map { $0.id }, entityName: "CommunityTopic")
        validateNoDuplicates(payload.proposedSolutions.map { $0.id }, entityName: "ProposedSolution")
        validateNoDuplicates(payload.meetingNotes.map { $0.id }, entityName: "MeetingNote")
        validateNoDuplicates(payload.communityAttachments.map { $0.id }, entityName: "CommunityAttachment")
        validateNoDuplicates(payload.attendance.map { $0.id }, entityName: "AttendanceRecord")
        validateNoDuplicates(payload.workCompletions.map { $0.id }, entityName: "WorkCompletionRecord")
        validateNoDuplicates(payload.projects.map { $0.id }, entityName: "Project")
        validateNoDuplicates(payload.projectAssignmentTemplates.map { $0.id }, entityName: "ProjectAssignmentTemplate")
        validateNoDuplicates(payload.projectSessions.map { $0.id }, entityName: "ProjectSession")
        validateNoDuplicates(payload.projectRoles.map { $0.id }, entityName: "ProjectRole")
        validateNoDuplicates(payload.projectTemplateWeeks.map { $0.id }, entityName: "ProjectTemplateWeek")
        validateNoDuplicates(payload.projectWeekRoleAssignments.map { $0.id }, entityName: "ProjectWeekRoleAssignment")
        
        if !duplicateErrors.isEmpty {
            throw NSError(
                domain: "BackupService",
                code: 1003,
                userInfo: [
                    NSLocalizedDescriptionKey: "Duplicate IDs found in backup:\n" + duplicateErrors.joined(separator: "\n")
                ]
            )
        }

        var warnings: [String] = []

        // Replace mode: validate backup in temporary container before wiping main store
        // This prevents the "all-or-nothing suicide pact" where a failed import leaves the user with zero data
        if mode == .replace {
            progress(0.35, "Validating backup in temporary container…")
            // Create a temporary in-memory container to validate the backup
            let tempConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            let tempContainer = try ModelContainer(for: AppSchema.schema, configurations: tempConfig)
            let tempContext = ModelContext(tempContainer)
            
            // Attempt to import into temporary container first
            do {
                // Import students first (required for foreign key validation)
                for dto in payload.students {
                    let s = Student(
                        id: dto.id,
                        firstName: dto.firstName,
                        lastName: dto.lastName,
                        birthday: dto.birthday,
                        level: dto.level == .upper ? .upper : .lower
                    )
                    s.dateStarted = dto.dateStarted
                    s.nextLessons = dto.nextLessons.map { $0.uuidString }
                    s.manualOrder = dto.manualOrder
                    tempContext.insert(s)
                }
                
                // Import lessons (required for foreign key validation)
                for dto in payload.lessons {
                    let l = Lesson(
                        id: dto.id,
                        name: dto.name,
                        subject: dto.subject,
                        group: dto.group,
                        orderInGroup: dto.orderInGroup,
                        subheading: dto.subheading,
                        writeUp: dto.writeUp
                    )
                    if let pages = dto.pagesFileRelativePath { l.pagesFileRelativePath = pages }
                    tempContext.insert(l)
                }
                
                // Import StudentLessons (critical for validation - tests foreign key integrity)
                for dto in payload.studentLessons {
                    let sl = StudentLesson(
                        id: dto.id,
                        lessonID: dto.lessonID,
                        studentIDs: dto.studentIDs,
                        createdAt: dto.createdAt,
                        scheduledFor: dto.scheduledFor,
                        givenAt: dto.givenAt,
                        notes: dto.notes,
                        needsPractice: dto.needsPractice,
                        needsAnotherPresentation: dto.needsAnotherPresentation,
                        followUpWork: dto.followUpWork
                    )
                    tempContext.insert(sl)
                }
                
                // Try to save the temporary container - if this fails, the backup is invalid
                try tempContext.save()
                
                // Validation successful - now safe to wipe main store
                progress(0.40, "Backup validated. Clearing existing data…")
                AppRouter.shared.signalAppDataWillBeReplaced()
                try deleteAll(modelContext: modelContext)
            } catch {
                // Validation failed - abort and throw error without wiping main store
                throw NSError(
                    domain: "BackupService",
                    code: 1004,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Backup validation failed. The backup file contains invalid data that cannot be imported. Your existing data has NOT been modified. Error: \(error.localizedDescription)"
                    ]
                )
            }
        }

        progress(0.65, "Importing records…")
        // Build lookup maps for quick linking
        var studentsByID: [UUID: Student] = [:]
        var lessonsByID: [UUID: Lesson] = [:]
        var topicsByID: [UUID: CommunityTopic] = [:]
        var workByID: [UUID: WorkContract] = [:]

        // Students
        for dto in payload.students {
            if (try? fetchOne(Student.self, id: dto.id, using: modelContext)) != nil {
                // merge: skip existing
                continue
            }
            let s = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: dto.level == .upper ? .upper : .lower
            )
            s.dateStarted = dto.dateStarted
            s.nextLessons = dto.nextLessons.map { $0.uuidString }
            s.manualOrder = dto.manualOrder
            modelContext.insert(s)
            studentsByID[s.id] = s
        }

        // Lessons
        for dto in payload.lessons {
            if (try? fetchOne(Lesson.self, id: dto.id, using: modelContext)) != nil { continue }
            let l = Lesson(
                id: dto.id,
                name: dto.name,
                subject: dto.subject,
                group: dto.group,
                orderInGroup: dto.orderInGroup,
                subheading: dto.subheading,
                writeUp: dto.writeUp
            )
            if let pages = dto.pagesFileRelativePath { l.pagesFileRelativePath = pages }
            modelContext.insert(l)
            lessonsByID[l.id] = l
        }

        // Community Topics
        for dto in payload.communityTopics {
            if (try? fetchOne(CommunityTopic.self, id: dto.id, using: modelContext)) != nil { continue }
            let t = CommunityTopic(
                id: dto.id,
                title: dto.title,
                issueDescription: dto.issueDescription,
                createdAt: dto.createdAt,
                addressedDate: dto.addressedDate,
                resolution: dto.resolution
            )
            t.raisedBy = dto.raisedBy
            t.tags = dto.tags
            modelContext.insert(t)
            topicsByID[t.id] = t
        }

        // Work Contracts
        for dto in payload.workContracts {
            if (try? fetchOne(WorkContract.self, id: dto.id, using: modelContext)) != nil { continue }
            let c = WorkContract(id: dto.id, studentID: dto.studentID, lessonID: dto.lessonID)
            c.presentationID = dto.presentationID
            c.statusRaw = dto.status
            c.scheduledDate = dto.scheduledDate
            c.createdAt = dto.createdAt ?? Date()
            c.completedAt = dto.completedAt
            c.kindRaw = dto.kind
            c.scheduledReasonRaw = dto.scheduledReason
            c.scheduledNote = dto.scheduledNote
            c.completionOutcome = dto.completionOutcome.flatMap { CompletionOutcome(rawValue: $0) }
            c.completionNote = dto.completionNote
            c.legacyStudentLessonID = dto.legacyStudentLessonID
            modelContext.insert(c)
            workByID[c.id] = c
        }

        // Work Plan Items
        for dto in payload.workPlanItems {
            if (try? fetchOne(WorkPlanItem.self, id: dto.id, using: modelContext)) != nil { continue }
            let item = WorkPlanItem(workID: dto.workID, scheduledDate: dto.scheduledDate, reason: nil, note: dto.note)
            item.id = dto.id
            let raw = dto.reason
            if !raw.isEmpty { item.reasonRaw = raw } else { item.reasonRaw = nil }
            item.note = dto.note
            modelContext.insert(item)
        }

        // Student Lessons
        for dto in payload.studentLessons {
            // Ensure referenced lesson exists
            let lessonExists = (try? fetchOne(Lesson.self, id: dto.lessonID, using: modelContext)) ?? nil
            if lessonExists == nil {
                warnings.append("Skipped StudentLesson \(dto.id.uuidString.prefix(8))... due to missing Lesson \(dto.lessonID.uuidString.prefix(8))...")
                continue
            }
            if (try? fetchOne(StudentLesson.self, id: dto.id, using: modelContext)) != nil { continue }
            let sl = StudentLesson(
                id: dto.id,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs,
                createdAt: dto.createdAt,
                scheduledFor: dto.scheduledFor,
                givenAt: dto.givenAt,
                notes: dto.notes,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork
            )
            // Link students if available
            var linked: [Student] = []
            for sid in dto.studentIDs {
                if let s = (try? fetchOne(Student.self, id: sid, using: modelContext)) ?? nil { linked.append(s) }
            }
            if !linked.isEmpty { sl.students = linked }
            modelContext.insert(sl)
        }

        // Notes and other simple models
        for dto in payload.scopedNotes {
            if (try? fetchOne(ScopedNote.self, id: dto.id, using: modelContext)) != nil { continue }
            let n = ScopedNote(
                id: dto.id,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                body: dto.body
            )
            n.scopeRaw = dto.scope.data(using: .utf8) ?? Data()
            n.legacyFingerprint = dto.legacyFingerprint
            
            if let slID = dto.studentLessonID, let sl = (try? fetchOne(StudentLesson.self, id: slID, using: modelContext)) ?? nil {
                n.studentLesson = sl
            }
            
            n.presentationID = dto.presentationID?.uuidString
            n.workContractID = dto.workContractID?.uuidString
            
            modelContext.insert(n)
        }

        for dto in payload.notes {
            if (try? fetchOne(Note.self, id: dto.id, using: modelContext)) != nil { continue }
            let n = Note(
                id: dto.id,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                body: dto.body,
                imagePath: dto.imagePath
            )
            n.isPinned = dto.isPinned
            
            if let data = dto.scope.data(using: .utf8),
               let s = try? JSONDecoder().decode(NoteScope.self, from: data) {
                n.scope = s
            }
            
            if let lID = dto.lessonID, let l = (try? fetchOne(Lesson.self, id: lID, using: modelContext)) ?? nil {
                n.lesson = l
            }
            
            modelContext.insert(n)
        }

        for dto in payload.nonSchoolDays {
            if (try? fetchOne(NonSchoolDay.self, id: dto.id, using: modelContext)) != nil { continue }
            let d = NonSchoolDay(id: dto.id, date: dto.date)
            d.reason = dto.reason
            modelContext.insert(d)
        }

        for dto in payload.schoolDayOverrides {
            if (try? fetchOne(SchoolDayOverride.self, id: dto.id, using: modelContext)) != nil { continue }
            let o = SchoolDayOverride(id: dto.id, date: dto.date)
            o.note = dto.note
            modelContext.insert(o)
        }

        // Student Meetings
        for dto in payload.studentMeetings {
            if (try? fetchOne(StudentMeeting.self, id: dto.id, using: modelContext)) != nil { continue }
            let m = StudentMeeting(id: dto.id, studentID: dto.studentID, date: dto.date)
            m.completed = dto.completed
            m.reflection = dto.reflection
            m.focus = dto.focus
            m.requests = dto.requests
            m.guideNotes = dto.guideNotes
            modelContext.insert(m)
        }

        // Presentations
        for dto in payload.presentations {
            if (try? fetchOne(Presentation.self, id: dto.id, using: modelContext)) != nil { continue }
            let p = Presentation(id: dto.id, createdAt: dto.createdAt, presentedAt: dto.presentedAt, lessonID: dto.lessonID, studentIDs: dto.studentIDs)
            p.legacyStudentLessonID = dto.legacyStudentLessonID
            p.lessonTitleSnapshot = dto.lessonTitleSnapshot
            p.lessonSubtitleSnapshot = dto.lessonSubtitleSnapshot
            modelContext.insert(p)
        }

        for dto in payload.proposedSolutions {
            if (try? fetchOne(ProposedSolution.self, id: dto.id, using: modelContext)) != nil { continue }
            let s = ProposedSolution(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                proposedBy: dto.proposedBy,
                createdAt: dto.createdAt,
                isAdopted: dto.isAdopted,
                topic: nil
            )
            if let tid = dto.topicID, let t = (try? fetchOne(CommunityTopic.self, id: tid, using: modelContext)) ?? nil {
                s.topic = t
            }
            modelContext.insert(s)
        }

        for dto in payload.meetingNotes {
            if (try? fetchOne(MeetingNote.self, id: dto.id, using: modelContext)) != nil { continue }
            let n = MeetingNote(id: dto.id, speaker: dto.speaker, content: dto.content, createdAt: dto.createdAt, topic: nil)
            if let tid = dto.topicID, let t = (try? fetchOne(CommunityTopic.self, id: tid, using: modelContext)) ?? nil {
                n.topic = t
            }
            modelContext.insert(n)
        }

        for dto in payload.communityAttachments {
            if (try? fetchOne(CommunityAttachment.self, id: dto.id, using: modelContext)) != nil { continue }
            let a = CommunityAttachment(id: dto.id, filename: dto.filename, kind: CommunityAttachment.Kind(rawValue: dto.kind) ?? .file, data: nil, createdAt: dto.createdAt, topic: nil)
            if let tid = dto.topicID, let t = (try? fetchOne(CommunityTopic.self, id: tid, using: modelContext)) ?? nil {
                a.topic = t
            }
            // NOTE: No binary data is restored by design.
            modelContext.insert(a)
        }

        // Attendance
        for dto in payload.attendance {
            if (try? fetchOne(AttendanceRecord.self, id: dto.id, using: modelContext)) != nil { continue }
            let absenceReason = dto.absenceReason.flatMap { AbsenceReason(rawValue: $0) } ?? .none
            let a = AttendanceRecord(id: dto.id, studentID: dto.studentID, date: dto.date, status: AttendanceStatus(rawValue: dto.status) ?? .unmarked, absenceReason: absenceReason, note: dto.note)
            modelContext.insert(a)
        }

        // Work Completions
        for dto in payload.workCompletions {
            if (try? fetchOne(WorkCompletionRecord.self, id: dto.id, using: modelContext)) != nil { continue }
            let r = WorkCompletionRecord(id: dto.id, workID: dto.workID, studentID: dto.studentID, completedAt: dto.completedAt, note: dto.note)
            modelContext.insert(r)
        }

        // Projects
        var clubsByID: [UUID: Project] = [:]
        for dto in payload.projects {
            if (try? fetchOne(Project.self, id: dto.id, using: modelContext)) != nil { continue }
            let c = Project(id: dto.id, createdAt: dto.createdAt, title: dto.title, bookTitle: dto.bookTitle, memberStudentIDs: dto.memberStudentIDs)
            modelContext.insert(c)
            clubsByID[c.id] = c
        }

        for dto in payload.projectRoles {
            if (try? fetchOne(ProjectRole.self, id: dto.id, using: modelContext)) != nil { continue }
            // CloudKit compatibility: Convert UUID to String for model
            let r = ProjectRole(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, title: dto.title, summary: dto.summary, instructions: dto.instructions)
            modelContext.insert(r)
        }

        var weeksByID: [UUID: ProjectTemplateWeek] = [:]
        for dto in payload.projectTemplateWeeks {
            if (try? fetchOne(ProjectTemplateWeek.self, id: dto.id, using: modelContext)) != nil { continue }
            // CloudKit compatibility: Convert UUID to String for model
            let w = ProjectTemplateWeek(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, weekIndex: dto.weekIndex, readingRange: dto.readingRange, agendaItemsJSON: dto.agendaItemsJSON, linkedLessonIDsJSON: dto.linkedLessonIDsJSON, workInstructions: dto.workInstructions)
            modelContext.insert(w)
            weeksByID[w.id] = w
        }

        for dto in payload.projectAssignmentTemplates {
            if (try? fetchOne(ProjectAssignmentTemplate.self, id: dto.id, using: modelContext)) != nil { continue }
            // CloudKit compatibility: Convert UUID to String for model
            let t = ProjectAssignmentTemplate(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, title: dto.title, instructions: dto.instructions, isShared: dto.isShared, defaultLinkedLessonID: dto.defaultLinkedLessonID)
            modelContext.insert(t)
        }

        for dto in payload.projectWeekRoleAssignments {
            if (try? fetchOne(ProjectWeekRoleAssignment.self, id: dto.id, using: modelContext)) != nil { continue }
            // CloudKit compatibility: Convert UUIDs to Strings for model
            let a = ProjectWeekRoleAssignment(id: dto.id, createdAt: dto.createdAt, weekID: dto.weekID, studentID: dto.studentID, roleID: dto.roleID, week: nil)
            // Link to week if present
            if let w = (try? fetchOne(ProjectTemplateWeek.self, id: dto.weekID, using: modelContext)) ?? nil {
                a.week = w
            }
            modelContext.insert(a)
        }

        for dto in payload.projectSessions {
            if (try? fetchOne(ProjectSession.self, id: dto.id, using: modelContext)) != nil { continue }
            // CloudKit compatibility: Convert UUIDs to Strings for model
            let s = ProjectSession(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, meetingDate: dto.meetingDate, chapterOrPages: dto.chapterOrPages, notes: dto.notes, agendaItemsJSON: dto.agendaItemsJSON, templateWeekID: dto.templateWeekID)
            modelContext.insert(s)
        }

        progress(0.90, "Saving…")
        try modelContext.save()
        
        // CRITICAL: Repair denormalized fields after bulk import
        // This ensures scheduledForDay is properly synced with scheduledFor
        progress(0.92, "Repairing denormalized fields…")
        let allStudentLessons = try modelContext.fetch(FetchDescriptor<StudentLesson>())
        var repairedCount = 0
        for sl in allStudentLessons {
            let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if sl.scheduledForDay != correct {
                sl.scheduledForDay = correct
                repairedCount += 1
            }
        }
        if repairedCount > 0 {
            try modelContext.save()
        }

        // Apply preferences
        applyPreferencesDTO(payload.preferences)

        AppRouter.shared.signalAppDataDidRestore()

        let counts = envelope.manifest.entityCounts
        progress(1.0, "Done")
        return BackupOperationSummary(
            kind: .import,
            fileName: url.lastPathComponent,
            formatVersion: envelope.formatVersion,
            encryptUsed: envelope.payload == nil,
            createdAt: envelope.createdAt,
            entityCounts: counts,
            warnings: warnings
        )
    }

    // MARK: - Helpers
    private func safeFetch<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        let descriptor = FetchDescriptor<T>()
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetches entities in batches to reduce memory pressure during backup operations.
    /// This processes entities in chunks (default 1000) rather than loading all at once.
    /// - Parameters:
    ///   - type: The entity type to fetch
    ///   - context: The ModelContext to fetch from
    ///   - batchSize: Number of entities to fetch per batch (default 1000)
    /// - Returns: All entities fetched in batches and accumulated
    private func safeFetchInBatches<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            
            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else {
                break
            }
            
            allEntities.append(contentsOf: batch)
            
            // If we got fewer than batchSize, we've reached the end
            if batch.count < batchSize {
                break
            }
            
            offset += batchSize
        }
        
        return allEntities
    }
    
    /// Fetches entities in batches with error handling for types that may have corrupted data.
    /// Similar to safeFetchInBatches but uses safeFetchWithErrorHandling logic per batch.
    /// - Parameters:
    ///   - type: The entity type to fetch
    ///   - context: The ModelContext to fetch from
    ///   - batchSize: Number of entities to fetch per batch (default 1000)
    /// - Returns: All entities fetched in batches and accumulated, with corrupted batches skipped
    private func safeFetchInBatchesWithErrorHandling<T: PersistentModel>(
        _ type: T.Type,
        using context: ModelContext,
        batchSize: Int = 1000
    ) -> [T] {
        var allEntities: [T] = []
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            
            // Try to fetch batch, skip if it fails (corrupted data handling)
            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else {
                // If fetch fails, we've either reached the end or hit corrupted data
                // In either case, stop fetching
                break
            }
            
            allEntities.append(contentsOf: batch)
            
            // If we got fewer than batchSize, we've reached the end
            if batch.count < batchSize {
                break
            }
            
            offset += batchSize
        }
        
        return allEntities
    }
    
    /// Safe fetch with additional error handling for entities that may have corrupted data.
    /// This is a workaround for SwiftData crashes when reading corrupted properties.
    private func safeFetchWithErrorHandling<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> [T] {
        // Try normal fetch first
        if let results = try? context.fetch(FetchDescriptor<T>()) {
            return results
        }
        // If fetch fails, return empty array to allow backup to continue
        // The backup will continue with other entities, preserving as much data as possible
        print("BackupService: Warning - Could not fetch \(String(describing: type)). Skipping this entity type.")
        return []
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
        // Use typed fetch descriptors per model to avoid KVC/Mirror on pure Swift @Model types
        if type == Student.self {
            let arr = try context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Lesson.self {
            let arr = try context.fetch(FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentLesson.self {
            let arr = try context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkContract.self {
            let arr = try context.fetch(FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkPlanItem.self {
            let arr = try context.fetch(FetchDescriptor<WorkPlanItem>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ScopedNote.self {
            let arr = try context.fetch(FetchDescriptor<ScopedNote>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Note.self {
            let arr = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == NonSchoolDay.self {
            let arr = try context.fetch(FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == SchoolDayOverride.self {
            let arr = try context.fetch(FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == StudentMeeting.self {
            let arr = try context.fetch(FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Presentation.self {
            let arr = try context.fetch(FetchDescriptor<Presentation>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == CommunityTopic.self {
            let arr = try context.fetch(FetchDescriptor<CommunityTopic>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProposedSolution.self {
            let arr = try context.fetch(FetchDescriptor<ProposedSolution>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == MeetingNote.self {
            let arr = try context.fetch(FetchDescriptor<MeetingNote>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == CommunityAttachment.self {
            let arr = try context.fetch(FetchDescriptor<CommunityAttachment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == AttendanceRecord.self {
            let arr = try context.fetch(FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == WorkCompletionRecord.self {
            let arr = try context.fetch(FetchDescriptor<WorkCompletionRecord>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == Project.self {
            let arr = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectAssignmentTemplate.self {
            let arr = try context.fetch(FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectSession.self {
            let arr = try context.fetch(FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectRole.self {
            let arr = try context.fetch(FetchDescriptor<ProjectRole>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectTemplateWeek.self {
            let arr = try context.fetch(FetchDescriptor<ProjectTemplateWeek>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == ProjectWeekRoleAssignment.self {
            let arr = try context.fetch(FetchDescriptor<ProjectWeekRoleAssignment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // Unknown type: return nil rather than relying on reflection/KVC
        return nil
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Extracts payload bytes directly from envelope JSON string to preserve exact encoding
    /// This avoids re-encoding differences that cause checksum mismatches
    private func extractPayloadBytes(from envelopeData: Data) throws -> Data? {
        guard let jsonString = String(data: envelopeData, encoding: .utf8) else {
            return nil
        }
        
        // Find the "payload" key in the JSON string and extract its value
        // This preserves the exact bytes that were used to calculate the checksum
        // Search for the key pattern that appears at the top level (after a comma or opening brace, followed by colon)
        let payloadKeyPattern = "\"payload\""
        var searchRange = jsonString.startIndex..<jsonString.endIndex
        
        // Find the payload key, ensuring it's a top-level key (preceded by { or , and whitespace)
        while let keyRange = jsonString.range(of: payloadKeyPattern, range: searchRange) {
            // Check if this is a top-level key by looking backwards
            var checkIndex = keyRange.lowerBound
            if checkIndex > jsonString.startIndex {
                checkIndex = jsonString.index(before: checkIndex)
                // Skip whitespace backwards
                while checkIndex > jsonString.startIndex && jsonString[checkIndex].isWhitespace {
                    checkIndex = jsonString.index(before: checkIndex)
                }
                // Should be preceded by { or ,
                if checkIndex >= jsonString.startIndex && (jsonString[checkIndex] == "{" || jsonString[checkIndex] == ",") {
                    // Found the payload key at top level
                    return extractPayloadValue(from: jsonString, startingAt: keyRange.upperBound)
                }
            } else if checkIndex == jsonString.startIndex {
                // Key is at the very start (after opening brace), this is valid
                return extractPayloadValue(from: jsonString, startingAt: keyRange.upperBound)
            }
            
            // Continue searching after this occurrence
            searchRange = keyRange.upperBound..<jsonString.endIndex
        }
        
        return nil
    }
    
    /// Extracts the JSON value starting from after the colon following a key
    private func extractPayloadValue(from jsonString: String, startingAt: String.Index) -> Data? {
        var searchStart = startingAt
        
        // Skip whitespace
        while searchStart < jsonString.endIndex && jsonString[searchStart].isWhitespace {
            searchStart = jsonString.index(after: searchStart)
        }
        guard searchStart < jsonString.endIndex && jsonString[searchStart] == ":" else {
            return nil
        }
        searchStart = jsonString.index(after: searchStart)
        
        // Skip whitespace after colon
        while searchStart < jsonString.endIndex && jsonString[searchStart].isWhitespace {
            searchStart = jsonString.index(after: searchStart)
        }
        
        // Extract the JSON value (object) - find matching braces
        guard searchStart < jsonString.endIndex && jsonString[searchStart] == "{" else {
            return nil
        }
        
        var braceCount = 0
        var inString = false
        var escapeNext = false
        let valueStart = searchStart
        var valueEnd = searchStart
        
        for i in jsonString[searchStart...].indices {
            let char = jsonString[i]
            
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                continue
            }
            
            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        valueEnd = jsonString.index(after: i)
                        break
                    }
                }
            }
        }
        
        guard braceCount == 0 else {
            return nil
        }
        
        // Extract the payload JSON substring and convert to Data
        let payloadJsonString = String(jsonString[valueStart..<valueEnd])
        return payloadJsonString.data(using: .utf8)
    }

    /// Compresses data using LZFSE algorithm
    private func compressData(_ data: Data) throws -> Data {
        let bufferSize = data.count + (data.count / 10) + 64 // Add overhead for compression
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }
        
        let sourceBuffer = data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        
        let compressedSize = compression_encode_buffer(
            destinationBuffer, bufferSize,
            sourceBuffer, data.count,
            nil,
            COMPRESSION_LZFSE
        )
        
        guard compressedSize > 0 else {
            throw NSError(domain: "BackupService", code: 1200, userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
        }
        
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
    
    /// Decompresses data using LZFSE algorithm
    /// Tries progressively larger buffers if initial estimate is insufficient
    private func decompressData(_ data: Data) throws -> Data {
        // Start with reasonable estimate (JSON typically compresses 2-4x with LZFSE)
        var bufferSize = data.count * 4
        let maxAttempts = 3
        var attempt = 0
        
        while attempt < maxAttempts {
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destinationBuffer.deallocate() }
            
            let sourceBuffer = data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
            
            let decompressedSize = compression_decode_buffer(
                destinationBuffer, bufferSize,
                sourceBuffer, data.count,
                nil,
                COMPRESSION_LZFSE
            )
            
            if decompressedSize > 0 {
                return Data(bytes: destinationBuffer, count: decompressedSize)
            }
            
            // Buffer too small, try larger size
            bufferSize *= 2
            attempt += 1
        }
        
        throw NSError(domain: "BackupService", code: 1201, userInfo: [NSLocalizedDescriptionKey: "Decompression failed: buffer size insufficient"])
    }
    
    /// Derives a symmetric encryption key from a password and salt using HKDF.
    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: password.data(using: .utf8)!)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKey, salt: salt, outputByteCount: 32)
    }

    private static let preferenceKeys: [String] = [
        "AttendanceEmail.enabled",
        "AttendanceEmail.to",
        "LessonAge.warningDays",
        "LessonAge.overdueDays",
        "WorkAge.warningDays",
        "WorkAge.overdueDays",
        "LessonAge.freshColorHex",
        "LessonAge.warningColorHex",
        "LessonAge.overdueColorHex",
        "WorkAge.freshColorHex",
        "WorkAge.warningColorHex",
        "WorkAge.overdueColorHex",
        "Backup.encrypt",
        "LastBackupTimeInterval",
        "lastBackupTimeInterval"
    ]

    private func buildPreferencesDTO() -> PreferencesDTO {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard
        var map: [String: PreferenceValueDTO] = [:]
        for key in Self.preferenceKeys {
            // Use synced store for synced keys, UserDefaults for local keys
            let obj: Any?
            if syncedStore.isSynced(key: key) {
                obj = syncedStore.get(key: key)
            } else {
                obj = defaults.object(forKey: key)
            }
            
            if let obj = obj {
                switch obj {
                case let b as Bool: map[key] = .bool(b)
                case let i as Int: map[key] = .int(i)
                case let d as Double: map[key] = .double(d)
                case let s as String: map[key] = .string(s)
                case let data as Data: map[key] = .data(data)
                case let date as Date: map[key] = .date(date)
                default:
                    // Fallback to string description
                    map[key] = .string(String(describing: obj))
                }
            }
        }
        return PreferencesDTO(values: map)
    }

    private func applyPreferencesDTO(_ dto: PreferencesDTO) {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard
        for (key, value) in dto.values {
            // Use synced store for synced keys, UserDefaults for local keys
            // Note: KVS supports Bool, Int, Double, String, and Data. Dates should be stored as Double (timeIntervalSinceReferenceDate).
            // For our current synced keys, we only use Bool, Int, String (no dates or data), so this is safe.
            if syncedStore.isSynced(key: key) {
                switch value {
                case .bool(let b): syncedStore.set(b, forKey: key)
                case .int(let i): syncedStore.set(i, forKey: key)
                case .double(let d): syncedStore.set(d, forKey: key)
                case .string(let s): syncedStore.set(s, forKey: key)
                case .data(let data): syncedStore.set(data as Any?, forKey: key)
                case .date(let date):
                    // Dates not directly supported in KVS - store as Double (timeIntervalSinceReferenceDate)
                    syncedStore.set(date.timeIntervalSinceReferenceDate, forKey: key)
                }
            } else {
                // Local keys go to UserDefaults (supports all types including Date)
                switch value {
                case .bool(let b): defaults.set(b, forKey: key)
                case .int(let i): defaults.set(i, forKey: key)
                case .double(let d): defaults.set(d, forKey: key)
                case .string(let s): defaults.set(s, forKey: key)
                case .data(let data): defaults.set(data, forKey: key)
                case .date(let date): defaults.set(date, forKey: key)
                }
            }
        }
    }

    private func deleteAll(modelContext: ModelContext) throws {
        // Use centralized entity registry
        for type in BackupEntityRegistry.allTypes {
            try? modelContext.delete(model: type)
        }
        try modelContext.save()
    }
}

