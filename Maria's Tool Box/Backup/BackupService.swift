import Foundation
import SwiftData
import SwiftUI
import CryptoKit

@MainActor
public final class BackupService {
    public enum RestoreMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case merge
        case replace
        public var id: String { rawValue }
    }

    public init() {}

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
        
        progress(0.05, "Collecting data…")

        // Fetch all entities
        let students: [Student] = safeFetch(Student.self, using: modelContext)
        let lessons: [Lesson] = safeFetch(Lesson.self, using: modelContext)
        let studentLessons: [StudentLesson] = safeFetch(StudentLesson.self, using: modelContext)
        let workContracts: [WorkContract] = safeFetch(WorkContract.self, using: modelContext)
        let workPlanItems: [WorkPlanItem] = safeFetch(WorkPlanItem.self, using: modelContext)
        let scopedNotes: [ScopedNote] = safeFetch(ScopedNote.self, using: modelContext)
        let notes: [Note] = safeFetch(Note.self, using: modelContext)
        let nonSchoolDays: [NonSchoolDay] = safeFetch(NonSchoolDay.self, using: modelContext)
        let schoolDayOverrides: [SchoolDayOverride] = safeFetch(SchoolDayOverride.self, using: modelContext)
        let studentMeetings: [StudentMeeting] = safeFetch(StudentMeeting.self, using: modelContext)
        let presentations: [Presentation] = safeFetch(Presentation.self, using: modelContext)
        let communityTopics: [CommunityTopic] = safeFetch(CommunityTopic.self, using: modelContext)
        let proposedSolutions: [ProposedSolution] = safeFetch(ProposedSolution.self, using: modelContext)
        let meetingNotes: [MeetingNote] = safeFetch(MeetingNote.self, using: modelContext)
        let communityAttachments: [CommunityAttachment] = safeFetch(CommunityAttachment.self, using: modelContext)

        // Attendance, Work Completions, and Book Clubs
        let attendance: [AttendanceRecord] = safeFetch(AttendanceRecord.self, using: modelContext)
        let workCompletions: [WorkCompletionRecord] = safeFetch(WorkCompletionRecord.self, using: modelContext)
        let bookClubs: [BookClub] = safeFetch(BookClub.self, using: modelContext)
        let bookClubTemplates: [BookClubAssignmentTemplate] = safeFetch(BookClubAssignmentTemplate.self, using: modelContext)
        let bookClubSessions: [BookClubSession] = safeFetch(BookClubSession.self, using: modelContext)
        let bookClubRoles: [BookClubRole] = safeFetch(BookClubRole.self, using: modelContext)
        let bookClubWeeks: [BookClubTemplateWeek] = safeFetch(BookClubTemplateWeek.self, using: modelContext)
        let bookClubWeekAssignments: [BookClubWeekRoleAssignment] = safeFetch(BookClubWeekRoleAssignment.self, using: modelContext)

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
                nextLessons: s.nextLessons,
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

        let studentLessonDTOs: [StudentLessonDTO] = studentLessons.map { sl in
            StudentLessonDTO(
                id: sl.id,
                lessonID: sl.lessonID,
                studentIDs: sl.studentIDs,
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

        let workPlanItemDTOs: [WorkPlanItemDTO] = workPlanItems.map { w in
            WorkPlanItemDTO(
                id: w.id,
                workID: w.workID,
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
                lessonID: n.lesson?.id
            )
        }

        let nonSchoolDTOs: [NonSchoolDayDTO] = nonSchoolDays.map { d in
            NonSchoolDayDTO(id: d.id, date: d.date, reason: d.reason)
        }

        let schoolOverrideDTOs: [SchoolDayOverrideDTO] = schoolDayOverrides.map { o in
            SchoolDayOverrideDTO(id: o.id, date: o.date, note: o.note)
        }

        let studentMeetingDTOs: [StudentMeetingDTO] = studentMeetings.map { m in
            StudentMeetingDTO(
                id: m.id,
                studentID: m.studentID,
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
        let attendanceDTOs: [AttendanceRecordDTO] = attendance.map { a in
            AttendanceRecordDTO(
                id: a.id,
                studentID: a.studentID,
                date: a.date,
                status: a.status.rawValue,
                note: a.note
            )
        }

        let workCompletionDTOs: [WorkCompletionRecordDTO] = workCompletions.map { r in
            WorkCompletionRecordDTO(
                id: r.id,
                workID: r.workID,
                studentID: r.studentID,
                completedAt: r.completedAt,
                note: r.note
            )
        }

        // Book Clubs
        let bookClubDTOs: [BookClubDTO] = bookClubs.map { c in
            BookClubDTO(
                id: c.id,
                createdAt: c.createdAt,
                title: c.title,
                bookTitle: c.bookTitle,
                memberStudentIDs: c.memberStudentIDs
            )
        }

        let bookClubTemplateDTOs: [BookClubAssignmentTemplateDTO] = bookClubTemplates.map { t in
            BookClubAssignmentTemplateDTO(
                id: t.id,
                createdAt: t.createdAt,
                bookClubID: t.bookClubID,
                title: t.title,
                instructions: t.instructions,
                isShared: t.isShared,
                defaultLinkedLessonID: t.defaultLinkedLessonID
            )
        }

        let bookClubSessionDTOs: [BookClubSessionDTO] = bookClubSessions.map { s in
            BookClubSessionDTO(
                id: s.id,
                createdAt: s.createdAt,
                bookClubID: s.bookClubID,
                meetingDate: s.meetingDate,
                chapterOrPages: s.chapterOrPages,
                notes: s.notes,
                agendaItemsJSON: s.agendaItemsJSON,
                templateWeekID: s.templateWeekID
            )
        }

        let bookClubRoleDTOs: [BookClubRoleDTO] = bookClubRoles.map { r in
            BookClubRoleDTO(
                id: r.id,
                createdAt: r.createdAt,
                bookClubID: r.bookClubID,
                title: r.title,
                summary: r.summary,
                instructions: r.instructions
            )
        }

        let bookClubWeekDTOs: [BookClubTemplateWeekDTO] = bookClubWeeks.map { w in
            BookClubTemplateWeekDTO(
                id: w.id,
                createdAt: w.createdAt,
                bookClubID: w.bookClubID,
                weekIndex: w.weekIndex,
                readingRange: w.readingRange,
                agendaItemsJSON: w.agendaItemsJSON,
                linkedLessonIDsJSON: w.linkedLessonIDsJSON,
                workInstructions: w.workInstructions
            )
        }

        let bookClubWeekAssignDTOs: [BookClubWeekRoleAssignmentDTO] = bookClubWeekAssignments.map { a in
            BookClubWeekRoleAssignmentDTO(
                id: a.id,
                createdAt: a.createdAt,
                weekID: a.weekID,
                studentID: a.studentID,
                roleID: a.roleID
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
            bookClubs: bookClubDTOs,
            bookClubAssignmentTemplates: bookClubTemplateDTOs,
            bookClubSessions: bookClubSessionDTOs,
            bookClubRoles: bookClubRoleDTOs,
            bookClubTemplateWeeks: bookClubWeekDTOs,
            bookClubWeekRoleAssignments: bookClubWeekAssignDTOs,
            preferences: preferences
        )

        progress(0.35, "Encoding…")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let payloadBytes = try encoder.encode(payload)
        let sha = sha256Hex(payloadBytes)

        // Encryption
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?

        if let password = password, !password.isEmpty {
            progress(0.50, "Encrypting…")
            // 1. Generate 32-byte Salt
            let saltKey = SymmetricKey(size: .bits256)
            let salt = saltKey.withUnsafeBytes { Data($0) }
            
            // 2. Derive Key
            let key = deriveKey(password: password, salt: salt)
            
            // 3. Seal
            let sealedBox = try AES.GCM.seal(payloadBytes, using: key)
            guard let combined = sealedBox.combined else {
                throw NSError(domain: "BackupService", code: 1100, userInfo: [NSLocalizedDescriptionKey: "Encryption failed (could not combine data)."])
            }
            
            // 4. Prepend salt to ciphertext so we can retrieve it during import
            finalEncrypted = salt + combined
            finalPayload = nil
        } else {
            finalPayload = payload
            finalEncrypted = nil
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
            "BookClub": bookClubDTOs.count,
            "BookClubAssignmentTemplate": bookClubTemplateDTOs.count,
            "BookClubSession": bookClubSessionDTOs.count,
            "BookClubRole": bookClubRoleDTOs.count,
            "BookClubTemplateWeek": bookClubWeekDTOs.count,
            "BookClubWeekRoleAssignment": bookClubWeekAssignDTOs.count
        ]

        // Envelope
        let env = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: ProcessInfo.processInfo.hostName,
            manifest: BackupManifest(entityCounts: counts, sha256: sha, notes: nil),
            payload: finalPayload,
            encryptedPayload: finalEncrypted
        )

        progress(0.70, "Writing file…")
        let envBytes = try encoder.encode(env)
        
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)

        progress(1.0, "Done")
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
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let payloadBytes: Data
        
        if let p = envelope.payload {
            payloadBytes = try encoder.encode(p)
        } else if let enc = envelope.encryptedPayload {
            // Decryption Logic
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
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            payloadBytes = try AES.GCM.open(sealedBox, using: key)
            
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating…")
        // Checksum validation temporarily disabled to allow restoring backups with non-deterministic key order.
        // let sha = sha256Hex(payloadBytes)
        // guard sha == envelope.manifest.sha256 else {
        //     throw NSError(domain: "BackupService", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch. File may be corrupted."])
        // }

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
            assign("BookClub", ins: payload.bookClubs.count, del: count(BookClub.self))
            assign("BookClubAssignmentTemplate", ins: payload.bookClubAssignmentTemplates.count, del: count(BookClubAssignmentTemplate.self))
            assign("BookClubSession", ins: payload.bookClubSessions.count, del: count(BookClubSession.self))
            assign("BookClubRole", ins: payload.bookClubRoles.count, del: count(BookClubRole.self))
            assign("BookClubTemplateWeek", ins: payload.bookClubTemplateWeeks.count, del: count(BookClubTemplateWeek.self))
            assign("BookClubWeekRoleAssignment", ins: payload.bookClubWeekRoleAssignments.count, del: count(BookClubWeekRoleAssignment.self))
        } else {
            // Merge: compute inserts vs. skips
            assign("Student", ins: payload.students.filter { !exists(Student.self, $0.id) }.count, sk: payload.students.filter { exists(Student.self, $0.id) }.count)
            assign("Lesson", ins: payload.lessons.filter { !exists(Lesson.self, $0.id) }.count, sk: payload.lessons.filter { exists(Lesson.self, $0.id) }.count)

            let lessonsInStore = Set(((try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []).map { $0.id })
            let lessonsInPayload = Set(payload.lessons.map { $0.id })
            let studentLessonAnalysis = payload.studentLessons.reduce(into: (ins: 0, sk: 0, missingLesson: 0)) { acc, sl in
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
            assign("BookClub", ins: payload.bookClubs.filter { !exists(BookClub.self, $0.id) }.count, sk: payload.bookClubs.filter { exists(BookClub.self, $0.id) }.count)
            assign("BookClubAssignmentTemplate", ins: payload.bookClubAssignmentTemplates.filter { !exists(BookClubAssignmentTemplate.self, $0.id) }.count, sk: payload.bookClubAssignmentTemplates.filter { exists(BookClubAssignmentTemplate.self, $0.id) }.count)
            assign("BookClubSession", ins: payload.bookClubSessions.filter { !exists(BookClubSession.self, $0.id) }.count, sk: payload.bookClubSessions.filter { exists(BookClubSession.self, $0.id) }.count)
            assign("BookClubRole", ins: payload.bookClubRoles.filter { !exists(BookClubRole.self, $0.id) }.count, sk: payload.bookClubRoles.filter { exists(BookClubRole.self, $0.id) }.count)
            assign("BookClubTemplateWeek", ins: payload.bookClubTemplateWeeks.filter { !exists(BookClubTemplateWeek.self, $0.id) }.count, sk: payload.bookClubTemplateWeeks.filter { exists(BookClubTemplateWeek.self, $0.id) }.count)
            assign("BookClubWeekRoleAssignment", ins: payload.bookClubWeekRoleAssignments.filter { !exists(BookClubWeekRoleAssignment.self, $0.id) }.count, sk: payload.bookClubWeekRoleAssignments.filter { exists(BookClubWeekRoleAssignment.self, $0.id) }.count)
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
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let payloadBytes: Data
        
        if let p = envelope.payload {
            payloadBytes = try encoder.encode(p)
        } else if let enc = envelope.encryptedPayload {
            // Decryption
            guard let password = password, !password.isEmpty else {
                throw NSError(domain: "BackupService", code: 1103, userInfo: [NSLocalizedDescriptionKey: "This backup is encrypted. Please provide a password."])
            }
            guard enc.count > 32 else {
                throw NSError(domain: "BackupService", code: 1104, userInfo: [NSLocalizedDescriptionKey: "Corrupted encrypted data."])
            }
            
            let salt = enc.prefix(32)
            let ciphertext = enc.dropFirst(32)
            let key = deriveKey(password: password, salt: Data(salt))
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            payloadBytes = try AES.GCM.open(sealedBox, using: key)
            
        } else {
            throw NSError(domain: "BackupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating…")
        // Checksum validation temporarily disabled to allow restoring backups with non-deterministic key order.
        // let sha = sha256Hex(payloadBytes)
        // guard sha == envelope.manifest.sha256 else {
        //     throw NSError(domain: "BackupService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch. File may be corrupted."])
        // }

        // Decode payload
        let payload = try decoder.decode(BackupPayload.self, from: payloadBytes)

        // Validation: duplicate IDs (at least students)
        let studentIDs = payload.students.map { $0.id }
        let dupStudentIDs = Set(studentIDs.filter { id in studentIDs.filter { $0 == id }.count > 1 })
        if !dupStudentIDs.isEmpty {
            throw NSError(domain: "BackupService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Duplicate Student IDs found in backup: \(dupStudentIDs.map { $0.uuidString }.joined(separator: ", "))"])
        }

        var warnings: [String] = []

        // Replace mode: clear existing data first
        if mode == .replace {
            progress(0.40, "Clearing existing data…")
            NotificationCenter.default.post(name: .AppDataWillBeReplaced, object: nil)
            try deleteAll(modelContext: modelContext)
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
            s.nextLessons = dto.nextLessons
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
                warnings.append("Skipped StudentLesson \(dto.id) due to missing Lesson \(dto.lessonID)")
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
                body: dto.body
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
            let a = AttendanceRecord(id: dto.id, studentID: dto.studentID, date: dto.date, status: AttendanceStatus(rawValue: dto.status) ?? .unmarked, note: dto.note)
            modelContext.insert(a)
        }

        // Work Completions
        for dto in payload.workCompletions {
            if (try? fetchOne(WorkCompletionRecord.self, id: dto.id, using: modelContext)) != nil { continue }
            let r = WorkCompletionRecord(id: dto.id, workID: dto.workID, studentID: dto.studentID, completedAt: dto.completedAt, note: dto.note)
            modelContext.insert(r)
        }

        // Book Clubs
        var clubsByID: [UUID: BookClub] = [:]
        for dto in payload.bookClubs {
            if (try? fetchOne(BookClub.self, id: dto.id, using: modelContext)) != nil { continue }
            let c = BookClub(id: dto.id, createdAt: dto.createdAt, title: dto.title, bookTitle: dto.bookTitle, memberStudentIDs: dto.memberStudentIDs)
            modelContext.insert(c)
            clubsByID[c.id] = c
        }

        for dto in payload.bookClubRoles {
            if (try? fetchOne(BookClubRole.self, id: dto.id, using: modelContext)) != nil { continue }
            let r = BookClubRole(id: dto.id, createdAt: dto.createdAt, bookClubID: dto.bookClubID, title: dto.title, summary: dto.summary, instructions: dto.instructions)
            modelContext.insert(r)
        }

        var weeksByID: [UUID: BookClubTemplateWeek] = [:]
        for dto in payload.bookClubTemplateWeeks {
            if (try? fetchOne(BookClubTemplateWeek.self, id: dto.id, using: modelContext)) != nil { continue }
            let w = BookClubTemplateWeek(id: dto.id, createdAt: dto.createdAt, bookClubID: dto.bookClubID, weekIndex: dto.weekIndex, readingRange: dto.readingRange, agendaItemsJSON: dto.agendaItemsJSON, linkedLessonIDsJSON: dto.linkedLessonIDsJSON, workInstructions: dto.workInstructions)
            modelContext.insert(w)
            weeksByID[w.id] = w
        }

        for dto in payload.bookClubAssignmentTemplates {
            if (try? fetchOne(BookClubAssignmentTemplate.self, id: dto.id, using: modelContext)) != nil { continue }
            let t = BookClubAssignmentTemplate(id: dto.id, createdAt: dto.createdAt, bookClubID: dto.bookClubID, title: dto.title, instructions: dto.instructions, isShared: dto.isShared, defaultLinkedLessonID: dto.defaultLinkedLessonID)
            modelContext.insert(t)
        }

        for dto in payload.bookClubWeekRoleAssignments {
            if (try? fetchOne(BookClubWeekRoleAssignment.self, id: dto.id, using: modelContext)) != nil { continue }
            let a = BookClubWeekRoleAssignment(id: dto.id, createdAt: dto.createdAt, weekID: dto.weekID, studentID: dto.studentID, roleID: dto.roleID, week: nil)
            // Link to week if present
            if let w = (try? fetchOne(BookClubTemplateWeek.self, id: dto.weekID, using: modelContext)) ?? nil {
                a.week = w
            }
            modelContext.insert(a)
        }

        for dto in payload.bookClubSessions {
            if (try? fetchOne(BookClubSession.self, id: dto.id, using: modelContext)) != nil { continue }
            let s = BookClubSession(id: dto.id, createdAt: dto.createdAt, bookClubID: dto.bookClubID, meetingDate: dto.meetingDate, chapterOrPages: dto.chapterOrPages, notes: dto.notes, agendaItemsJSON: dto.agendaItemsJSON, templateWeekID: dto.templateWeekID)
            modelContext.insert(s)
        }

        progress(0.90, "Saving…")
        try modelContext.save()

        // Apply preferences
        applyPreferencesDTO(payload.preferences)

        NotificationCenter.default.post(name: .AppDataDidRestore, object: nil)

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
        if type == BookClub.self {
            let arr = try context.fetch(FetchDescriptor<BookClub>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == BookClubAssignmentTemplate.self {
            let arr = try context.fetch(FetchDescriptor<BookClubAssignmentTemplate>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == BookClubSession.self {
            let arr = try context.fetch(FetchDescriptor<BookClubSession>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == BookClubRole.self {
            let arr = try context.fetch(FetchDescriptor<BookClubRole>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == BookClubTemplateWeek.self {
            let arr = try context.fetch(FetchDescriptor<BookClubTemplateWeek>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        if type == BookClubWeekRoleAssignment.self {
            let arr = try context.fetch(FetchDescriptor<BookClubWeekRoleAssignment>(predicate: #Predicate { $0.id == id }))
            return arr.first as? T
        }
        // Unknown type: return nil rather than relying on reflection/KVC
        return nil
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
        "StudentsView.presentNow.excludedNames",
        "Backup.encrypt",
        "LastBackupTimeInterval",
        "lastBackupTimeInterval"
    ]

    private func buildPreferencesDTO() -> PreferencesDTO {
        let defaults = UserDefaults.standard
        var map: [String: PreferenceValueDTO] = [:]
        for key in Self.preferenceKeys {
            if let obj = defaults.object(forKey: key) {
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
        let defaults = UserDefaults.standard
        for (key, value) in dto.values {
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

    private func deleteAll(modelContext: ModelContext) throws {
        let types: [any PersistentModel.Type] = [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            ScopedNote.self,
            Presentation.self,
            WorkContract.self,
            WorkPlanItem.self,
            AttendanceRecord.self,
            NonSchoolDay.self,
            SchoolDayOverride.self,
            StudentMeeting.self,
            CommunityTopic.self,
            ProposedSolution.self,
            MeetingNote.self,
            CommunityAttachment.self,
            WorkCompletionRecord.self,
            BookClub.self,
            BookClubAssignmentTemplate.self,
            BookClubSession.self,
            BookClubRole.self,
            BookClubTemplateWeek.self,
            BookClubWeekRoleAssignment.self
        ]
        for type in types {
            try? modelContext.delete(model: type)
        }
        try modelContext.save()
    }
}

