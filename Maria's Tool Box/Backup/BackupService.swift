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
        encrypt: Bool,
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        progress(0.05, "Collecting data…")

        // Fetch all entities we know about. If a model isn't present in this build, we simply leave that array empty.
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

        // Map to DTOs (exclude any imported/binary file data)
        let studentDTOs: [StudentDTO] = students.map { s in
            let levelRaw = (s as AnyObject).value(forKey: "levelRaw") as? String
            let levelProp = (s as AnyObject).value(forKey: "level") as? String
            let levelLower = levelRaw?.lowercased() ?? levelProp?.lowercased() ?? ""
            let level: StudentDTO.Level = (levelLower == "upper") ? .upper : .lower
            return StudentDTO(
                id: s.id,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                dateStarted: (s as AnyObject).value(forKey: "dateStarted") as? Date,
                level: level,
                nextLessons: (s as AnyObject).value(forKey: "nextLessons") as? [UUID] ?? [],
                manualOrder: (s as? Student)?.manualOrder ?? ((s as AnyObject).value(forKey: "manualOrder") as? Int ?? 0),
                createdAt: (s as AnyObject).value(forKey: "createdAt") as? Date,
                updatedAt: (s as AnyObject).value(forKey: "updatedAt") as? Date
            )
        }

        let lessonDTOs: [LessonDTO] = lessons.map { l in
            return LessonDTO(
                id: l.id,
                name: l.name,
                subject: l.subject,
                group: l.group,
                orderInGroup: l.orderInGroup,
                subheading: l.subheading,
                writeUp: l.writeUp,
                createdAt: (l as AnyObject).value(forKey: "createdAt") as? Date,
                updatedAt: (l as AnyObject).value(forKey: "updatedAt") as? Date,
                pagesFileRelativePath: (l as AnyObject).value(forKey: "pagesFileRelativePath") as? String
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
                isPresented: ((sl as AnyObject).value(forKey: "isPresented") as? Bool) ?? (sl.givenAt != nil),
                notes: sl.notes,
                needsPractice: sl.needsPractice,
                needsAnotherPresentation: sl.needsAnotherPresentation,
                followUpWork: sl.followUpWork,
                studentGroupKey: (sl as AnyObject).value(forKey: "studentGroupKey") as? String
            )
        }

        let workContractDTOs: [WorkContractDTO] = workContracts.map { c in
            WorkContractDTO(
                id: c.id,
                studentID: c.studentID,
                lessonID: c.lessonID,
                presentationID: (c as AnyObject).value(forKey: "presentationID") as? String,
                status: (c as AnyObject).value(forKey: "statusRaw") as? String ?? "",
                scheduledDate: (c as AnyObject).value(forKey: "scheduledDate") as? Date,
                createdAt: (c as AnyObject).value(forKey: "createdAt") as? Date,
                completedAt: (c as AnyObject).value(forKey: "completedAt") as? Date,
                kind: (c as AnyObject).value(forKey: "kind") as? String,
                scheduledReason: (c as AnyObject).value(forKey: "scheduledReason") as? String,
                scheduledNote: (c as AnyObject).value(forKey: "scheduledNote") as? String,
                completionOutcome: (c as AnyObject).value(forKey: "completionOutcome") as? String,
                completionNote: (c as AnyObject).value(forKey: "completionNote") as? String,
                legacyStudentLessonID: (c as AnyObject).value(forKey: "legacyStudentLessonID") as? String
            )
        }

        let workPlanItemDTOs: [WorkPlanItemDTO] = workPlanItems.map { w in
            WorkPlanItemDTO(
                id: w.id,
                workID: w.workID,
                scheduledDate: w.scheduledDate,
                reason: ((w as AnyObject).value(forKey: "reasonRaw") as? String) ?? ((w as AnyObject).value(forKey: "reason") as? String ?? ""),
                note: w.note
            )
        }

        let scopedNoteDTOs: [ScopedNoteDTO] = scopedNotes.map { n in
            ScopedNoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                scope: (n as AnyObject).value(forKey: "scopeRaw") as? String ?? ((n as AnyObject).value(forKey: "scope") as? String ?? ""),
                legacyFingerprint: (n as AnyObject).value(forKey: "legacyFingerprint") as? String,
                studentLessonID: (n as AnyObject).value(forKey: "studentLessonID") as? UUID,
                workID: (n as AnyObject).value(forKey: "workID") as? UUID,
                presentationID: (n as AnyObject).value(forKey: "presentationID") as? UUID,
                workContractID: (n as AnyObject).value(forKey: "workContractID") as? UUID
            )
        }

        let noteDTOs: [NoteDTO] = notes.map { n in
            NoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                isPinned: (n as AnyObject).value(forKey: "isPinned") as? Bool ?? false,
                scope: (n as AnyObject).value(forKey: "scopeRaw") as? String ?? ((n as AnyObject).value(forKey: "scope") as? String ?? ""),
                lessonID: (n as AnyObject).value(forKey: "lessonID") as? UUID,
                workID: (n as AnyObject).value(forKey: "workID") as? UUID
            )
        }

        let nonSchoolDTOs: [NonSchoolDayDTO] = nonSchoolDays.map { d in
            NonSchoolDayDTO(id: d.id, date: d.date, reason: (d as AnyObject).value(forKey: "reason") as? String)
        }

        let schoolOverrideDTOs: [SchoolDayOverrideDTO] = schoolDayOverrides.map { o in
            SchoolDayOverrideDTO(id: o.id, date: o.date, note: (o as AnyObject).value(forKey: "note") as? String)
        }

        let studentMeetingDTOs: [StudentMeetingDTO] = studentMeetings.map { m in
            StudentMeetingDTO(
                id: m.id,
                studentID: (m as AnyObject).value(forKey: "studentID") as? UUID ?? UUID(),
                date: m.date,
                completed: (m as AnyObject).value(forKey: "completed") as? Bool ?? false,
                reflection: (m as AnyObject).value(forKey: "reflection") as? String ?? "",
                focus: (m as AnyObject).value(forKey: "focus") as? String ?? "",
                requests: (m as AnyObject).value(forKey: "requests") as? String ?? "",
                guideNotes: (m as AnyObject).value(forKey: "guideNotes") as? String ?? ""
            )
        }

        let presentationDTOs: [PresentationDTO] = presentations.map { p in
            PresentationDTO(
                id: p.id,
                createdAt: p.createdAt,
                presentedAt: (p as AnyObject).value(forKey: "presentedAt") as? Date ?? p.createdAt,
                lessonID: (p as AnyObject).value(forKey: "lessonID") as? String ?? "",
                studentIDs: (p as AnyObject).value(forKey: "studentIDs") as? [String] ?? [],
                legacyStudentLessonID: (p as AnyObject).value(forKey: "legacyStudentLessonID") as? String,
                lessonTitleSnapshot: (p as AnyObject).value(forKey: "lessonTitleSnapshot") as? String,
                lessonSubtitleSnapshot: (p as AnyObject).value(forKey: "lessonSubtitleSnapshot") as? String
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
            preferences: preferences
        )

        progress(0.35, "Encoding…")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadBytes = try encoder.encode(payload)
        let sha = sha256Hex(payloadBytes)

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
            "CommunityAttachment": attachmentDTOs.count
        ]

        // Envelope
        let env = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            device: Host.current().localizedName ?? "",
            manifest: BackupManifest(entityCounts: counts, sha256: sha, notes: nil),
            payload: encrypt ? nil : payload,
            encryptedPayload: encrypt ? payloadBytes : nil
        )

        progress(0.70, "Writing file…")
        let envBytes = try encoder.encode(env)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try envBytes.write(to: url, options: .atomic)

        progress(1.0, "Done")
        return BackupOperationSummary(
            kind: .export,
            fileName: url.lastPathComponent,
            formatVersion: BackupFile.formatVersion,
            encryptUsed: encrypt,
            createdAt: Date(),
            entityCounts: counts,
            warnings: []
        )
    }

    // MARK: - Restore Preview
    public func previewImport(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        progress: @escaping (Double, String) -> Void
    ) async throws -> RestorePreview {
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
            payloadBytes = enc
        } else {
            throw NSError(domain: "BackupService", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating…")
        // Checksum
        let sha = sha256Hex(payloadBytes)
        guard sha == envelope.manifest.sha256 else {
            throw NSError(domain: "BackupService", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch. File may be corrupted."])
        }

        // Decode payload (support legacy v1 preferences)
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: payloadBytes)
        } catch {
            struct LegacyPayload: Codable {
                var items: [ItemDTO] = []
                var students: [StudentDTO] = []
                var lessons: [LessonDTO] = []
                var studentLessons: [StudentLessonDTO] = []
                var works: [WorkDTO] = []
                var attendance: [AttendanceRecordDTO] = []
                var workCompletions: [WorkCompletionRecordDTO] = []
                var workCheckIns: [WorkCheckInDTO] = []
                var workContracts: [WorkContractDTO] = []
                var workPlanItems: [WorkPlanItemDTO] = []
                var scopedNotes: [ScopedNoteDTO] = []
                var notes: [NoteDTO] = []
                var nonSchoolDays: [NonSchoolDayDTO] = []
                var schoolDayOverrides: [SchoolDayOverrideDTO] = []
                var studentMeetings: [StudentMeetingDTO] = []
                var presentations: [PresentationDTO] = []
                var communityTopics: [CommunityTopicDTO] = []
                var proposedSolutions: [ProposedSolutionDTO] = []
                var meetingNotes: [MeetingNoteDTO] = []
                var communityAttachments: [CommunityAttachmentDTO] = []
                var preferences: [String: String]
            }
            let legacy = try decoder.decode(LegacyPayload.self, from: payloadBytes)
            let pref = PreferencesDTO(values: Dictionary(uniqueKeysWithValues: legacy.preferences.map { ($0.key, PreferenceValueDTO.string($0.value)) }))
            payload = BackupPayload(
                items: legacy.items,
                students: legacy.students,
                lessons: legacy.lessons,
                studentLessons: legacy.studentLessons,
                workContracts: legacy.workContracts,
                workPlanItems: legacy.workPlanItems,
                scopedNotes: legacy.scopedNotes,
                notes: legacy.notes,
                nonSchoolDays: legacy.nonSchoolDays,
                schoolDayOverrides: legacy.schoolDayOverrides,
                studentMeetings: legacy.studentMeetings,
                presentations: legacy.presentations,
                communityTopics: legacy.communityTopics,
                proposedSolutions: legacy.proposedSolutions,
                meetingNotes: legacy.meetingNotes,
                communityAttachments: legacy.communityAttachments,
                preferences: pref
            )
        }

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
        progress: @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
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
            payloadBytes = enc
        } else {
            throw NSError(domain: "BackupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup file missing payload."])
        }

        progress(0.20, "Validating…")
        // Checksum
        let sha = sha256Hex(payloadBytes)
        guard sha == envelope.manifest.sha256 else {
            throw NSError(domain: "BackupService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch. File may be corrupted."])
        }

        // Decode payload (support legacy v1 preferences)
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: payloadBytes)
        } catch {
            // Try legacy where preferences are [String: String]
            struct LegacyPayload: Codable {
                var items: [ItemDTO] = []
                var students: [StudentDTO] = []
                var lessons: [LessonDTO] = []
                var studentLessons: [StudentLessonDTO] = []
                var works: [WorkDTO] = []
                var attendance: [AttendanceRecordDTO] = []
                var workCompletions: [WorkCompletionRecordDTO] = []
                var workCheckIns: [WorkCheckInDTO] = []
                var workContracts: [WorkContractDTO] = []
                var workPlanItems: [WorkPlanItemDTO] = []
                var scopedNotes: [ScopedNoteDTO] = []
                var notes: [NoteDTO] = []
                var nonSchoolDays: [NonSchoolDayDTO] = []
                var schoolDayOverrides: [SchoolDayOverrideDTO] = []
                var studentMeetings: [StudentMeetingDTO] = []
                var presentations: [PresentationDTO] = []
                var communityTopics: [CommunityTopicDTO] = []
                var proposedSolutions: [ProposedSolutionDTO] = []
                var meetingNotes: [MeetingNoteDTO] = []
                var communityAttachments: [CommunityAttachmentDTO] = []
                var preferences: [String: String]
            }
            let legacy = try decoder.decode(LegacyPayload.self, from: payloadBytes)
            let pref = PreferencesDTO(values: Dictionary(uniqueKeysWithValues: legacy.preferences.map { ($0.key, PreferenceValueDTO.string($0.value)) }))
            payload = BackupPayload(
                items: legacy.items,
                students: legacy.students,
                lessons: legacy.lessons,
                studentLessons: legacy.studentLessons,
                workContracts: legacy.workContracts,
                workPlanItems: legacy.workPlanItems,
                scopedNotes: legacy.scopedNotes,
                notes: legacy.notes,
                nonSchoolDays: legacy.nonSchoolDays,
                schoolDayOverrides: legacy.schoolDayOverrides,
                studentMeetings: legacy.studentMeetings,
                presentations: legacy.presentations,
                communityTopics: legacy.communityTopics,
                proposedSolutions: legacy.proposedSolutions,
                meetingNotes: legacy.meetingNotes,
                communityAttachments: legacy.communityAttachments,
                preferences: pref
            )
        }

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
            if let ds = dto.dateStarted { (s as AnyObject).setValue(ds, forKey: "dateStarted") }
            (s as AnyObject).setValue(dto.nextLessons, forKey: "nextLessons")
            (s as AnyObject).setValue(dto.manualOrder, forKey: "manualOrder")
            if let created = dto.createdAt { (s as AnyObject).setValue(created, forKey: "createdAt") }
            if let updated = dto.updatedAt { (s as AnyObject).setValue(updated, forKey: "updatedAt") }
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
            if let created = dto.createdAt { (l as AnyObject).setValue(created, forKey: "createdAt") }
            if let updated = dto.updatedAt { (l as AnyObject).setValue(updated, forKey: "updatedAt") }
            if let pages = dto.pagesFileRelativePath { (l as AnyObject).setValue(pages, forKey: "pagesFileRelativePath") }
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
            if let pid = dto.presentationID { (c as AnyObject).setValue(pid, forKey: "presentationID") }
            (c as AnyObject).setValue(dto.status, forKey: "statusRaw")
            if let d = dto.scheduledDate { (c as AnyObject).setValue(d, forKey: "scheduledDate") }
            if let d = dto.createdAt { (c as AnyObject).setValue(d, forKey: "createdAt") }
            if let d = dto.completedAt { (c as AnyObject).setValue(d, forKey: "completedAt") }
            if let v = dto.kind { (c as AnyObject).setValue(v, forKey: "kind") }
            if let v = dto.scheduledReason { (c as AnyObject).setValue(v, forKey: "scheduledReason") }
            if let v = dto.scheduledNote { (c as AnyObject).setValue(v, forKey: "scheduledNote") }
            if let v = dto.completionOutcome { (c as AnyObject).setValue(v, forKey: "completionOutcome") }
            if let v = dto.completionNote { (c as AnyObject).setValue(v, forKey: "completionNote") }
            if let v = dto.legacyStudentLessonID { (c as AnyObject).setValue(v, forKey: "legacyStudentLessonID") }
            modelContext.insert(c)
            workByID[c.id] = c
        }

        // Work Plan Items
        for dto in payload.workPlanItems {
            if (try? fetchOne(WorkPlanItem.self, id: dto.id, using: modelContext)) != nil { continue }
            let item = WorkPlanItem(workID: dto.workID, scheduledDate: dto.scheduledDate, reason: nil, note: dto.note)
            (item as AnyObject).setValue(dto.id, forKey: "id")
            let raw = dto.reason
            if !raw.isEmpty {
                // Best-effort: try KVC set
                (item as AnyObject).setValue(raw, forKey: "reasonRaw")
            }
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
            // Link relationships if the model has them
            if let l = lessonExists { sl.lesson = l }
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
            (n as AnyObject).setValue(dto.scope, forKey: "scopeRaw")
            (n as AnyObject).setValue(dto.legacyFingerprint, forKey: "legacyFingerprint")
            (n as AnyObject).setValue(dto.studentLessonID, forKey: "studentLessonID")
            (n as AnyObject).setValue(dto.workID, forKey: "workID")
            (n as AnyObject).setValue(dto.presentationID, forKey: "presentationID")
            (n as AnyObject).setValue(dto.workContractID, forKey: "workContractID")
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
            (n as AnyObject).setValue(dto.isPinned, forKey: "isPinned")
            (n as AnyObject).setValue(dto.scope, forKey: "scopeRaw")
            (n as AnyObject).setValue(dto.lessonID, forKey: "lessonID")
            (n as AnyObject).setValue(dto.workID, forKey: "workID")
            modelContext.insert(n)
        }

        for dto in payload.nonSchoolDays {
            if (try? fetchOne(NonSchoolDay.self, id: dto.id, using: modelContext)) != nil { continue }
            let d = NonSchoolDay(id: dto.id, date: dto.date)
            (d as AnyObject).setValue(dto.reason, forKey: "reason")
            modelContext.insert(d)
        }

        for dto in payload.schoolDayOverrides {
            if (try? fetchOne(SchoolDayOverride.self, id: dto.id, using: modelContext)) != nil { continue }
            let o = SchoolDayOverride(id: dto.id, date: dto.date)
            (o as AnyObject).setValue(dto.note, forKey: "note")
            modelContext.insert(o)
        }

        // Student Meetings
        for dto in payload.studentMeetings {
            if (try? fetchOne(StudentMeeting.self, id: dto.id, using: modelContext)) != nil { continue }
            let m = StudentMeeting(id: dto.id, studentID: dto.studentID, date: dto.date)
            (m as AnyObject).setValue(dto.completed, forKey: "completed")
            (m as AnyObject).setValue(dto.reflection, forKey: "reflection")
            (m as AnyObject).setValue(dto.focus, forKey: "focus")
            (m as AnyObject).setValue(dto.requests, forKey: "requests")
            (m as AnyObject).setValue(dto.guideNotes, forKey: "guideNotes")
            modelContext.insert(m)
        }

        // Presentations
        for dto in payload.presentations {
            if (try? fetchOne(Presentation.self, id: dto.id, using: modelContext)) != nil { continue }
            let p = Presentation(id: dto.id, createdAt: dto.createdAt, presentedAt: dto.presentedAt, lessonID: dto.lessonID, studentIDs: dto.studentIDs)
            (p as AnyObject).setValue(dto.legacyStudentLessonID, forKey: "legacyStudentLessonID")
            (p as AnyObject).setValue(dto.lessonTitleSnapshot, forKey: "lessonTitleSnapshot")
            (p as AnyObject).setValue(dto.lessonSubtitleSnapshot, forKey: "lessonSubtitleSnapshot")
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

        progress(0.90, "Saving…")
        try modelContext.save()

        // Apply preferences
        applyPreferencesDTO(payload.preferences)

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
        let all = try context.fetch(FetchDescriptor<T>())
        return all.first { (obj: T) in
            ((obj as AnyObject).value(forKey: "id") as? UUID) == id
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
            CommunityAttachment.self
        ]
        for type in types {
            try? modelContext.delete(model: type)
        }
        try modelContext.save()
    }
}

