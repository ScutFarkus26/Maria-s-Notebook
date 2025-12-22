import Foundation
import SwiftData
import CryptoKit

#if os(macOS)
private enum ObjCHost {
    static func currentLocalizedName() throws -> String? {
        // Use Foundation's Host via Objective-C runtime indirectly to avoid direct reference if unavailable on other platforms
        return Host.current().localizedName
    }
}
#endif

actor BackupService {
    enum RestoreMode { case replace, merge }

    struct BackupValidationResult: Sendable {
        var warnings: [String] = []
        var errors: [String] = []
    }

    struct BackupOperationSummary: Sendable {
        let fileName: String
        let formatVersion: Int
        let encryptUsed: Bool
        let createdAt: Date
        let entityCounts: [String: Int]
        let warnings: [String]
    }

    // MARK: - Public API
    func exportBackup(
        modelContext: ModelContext,
        to url: URL,
        encrypt: Bool,
        progress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        progress(0.02, "Fetching data…")

        var payload = try await Self.buildPayload(using: modelContext)

        // Update preferences to include Backup.encrypt
        let payloadSnapshot = payload
        let updatedPayload: BackupPayload = await MainActor.run {
            var preferencesWithEncrypt = payloadSnapshot.preferences
            preferencesWithEncrypt.values["Backup.encrypt"] = .bool(encrypt)
            return BackupPayload(
                items: payloadSnapshot.items,
                students: payloadSnapshot.students,
                lessons: payloadSnapshot.lessons,
                studentLessons: payloadSnapshot.studentLessons,
                works: payloadSnapshot.works,
                attendance: payloadSnapshot.attendance,
                workCompletions: payloadSnapshot.workCompletions,
                workCheckIns: payloadSnapshot.workCheckIns,
                workContracts: payloadSnapshot.workContracts,
                workPlanItems: payloadSnapshot.workPlanItems,
                scopedNotes: payloadSnapshot.scopedNotes,
                notes: payloadSnapshot.notes,
                nonSchoolDays: payloadSnapshot.nonSchoolDays,
                schoolDayOverrides: payloadSnapshot.schoolDayOverrides,
                studentMeetings: payloadSnapshot.studentMeetings,
                presentations: payloadSnapshot.presentations,
                communityTopics: payloadSnapshot.communityTopics,
                proposedSolutions: payloadSnapshot.proposedSolutions,
                meetingNotes: payloadSnapshot.meetingNotes,
                communityAttachments: payloadSnapshot.communityAttachments,
                preferences: preferencesWithEncrypt
            )
        }
        payload = updatedPayload

        progress(0.10, "Encoding payload…")
        let payloadForEncoding = payload
        let payloadBytes: Data = try await MainActor.run {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payloadForEncoding)
        }

        progress(0.16, "Computing checksum…")
        let checksum = Self.sha256Hex(of: payloadBytes)

        var encryptedData: Data? = nil
        if encrypt {
            progress(0.22, "Encrypting…")
            let keyData = try await Self.obtainKey()
            encryptedData = try Self.encryptAESGCM(plaintext: payloadBytes, keyData: keyData)
        }

        let createdAt = Date()
        let entityCounts = Self.counts(from: payload)
        let formatVersion = await MainActor.run { BackupFile.formatVersion }
        let payloadForEnvelope = payload
        let encryptedForEnvelope = encryptedData

        let envelopeBytes: Data = try await MainActor.run {
            let manifest = BackupManifest(entityCounts: entityCounts, sha256: checksum, notes: nil)
            let envelope = BackupEnvelope(
                formatVersion: formatVersion,
                createdAt: createdAt,
                appBuild: Self.appBuild(),
                appVersion: Self.appVersion(),
                device: Self.deviceString(),
                manifest: manifest,
                payload: encrypt ? nil : payloadForEnvelope,
                encryptedPayload: encryptedForEnvelope
            )
            let envEncoder = JSONEncoder()
            envEncoder.dateEncodingStrategy = .iso8601
            return try envEncoder.encode(envelope)
        }

        progress(0.40, "Writing file…")
        try Self.atomicWrite(data: envelopeBytes, to: url)

        let warnings = ["Files/attachments are not included in backups by design."]
        let summary = BackupOperationSummary(
            fileName: url.lastPathComponent,
            formatVersion: formatVersion,
            encryptUsed: encrypt,
            createdAt: createdAt,
            entityCounts: entityCounts,
            warnings: warnings
        )
        progress(1.0, "Backup complete: \(entityCounts.values.reduce(0, +)) records")
        return summary
    }

    func importBackup(
        modelContext: ModelContext,
        from url: URL,
        mode: RestoreMode,
        progress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> BackupOperationSummary {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    var warnings: [String] = ["Files/attachments are not included in backups by design."]
                    progress(0.02, "Reading backup…")
                    let data = try Data(contentsOf: url)

                    let envInfo = try await MainActor.run { () -> (formatVersion: Int, createdAt: Date, encryptedPayload: Data?, payloadBytes: Data?, manifestSha: String, entityCounts: [String:Int]) in
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
                        let payloadBytes: Data? = {
                            if let payload = envelope.payload {
                                let enc = JSONEncoder()
                                enc.dateEncodingStrategy = .iso8601
                                return try? enc.encode(payload)
                            } else {
                                return nil
                            }
                        }()
                        return (envelope.formatVersion, envelope.createdAt, envelope.encryptedPayload, payloadBytes, envelope.manifest.sha256, envelope.manifest.entityCounts)
                    }

                    let currentFormat = await MainActor.run { BackupFile.formatVersion }
                    guard envInfo.formatVersion <= currentFormat else {
                        throw NSError(domain: "BackupService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Backup was created by a newer app version."])
                    }

                    progress(0.10, "Decoding payload…")
                    let payloadBytes: Data
                    if let encrypted = envInfo.encryptedPayload {
                        let keyData = try await Self.obtainKey()
                        payloadBytes = try Self.decryptAESGCM(ciphertext: encrypted, keyData: keyData)
                    } else if let bytes = envInfo.payloadBytes {
                        payloadBytes = bytes
                    } else {
                        throw NSError(domain: "BackupService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Backup payload missing."])
                    }

                    progress(0.16, "Verifying checksum…")
                    let checksum = Self.sha256Hex(of: payloadBytes)
                    guard checksum == envInfo.manifestSha else {
                        throw NSError(domain: "BackupService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Backup file is corrupted (checksum mismatch)."])
                    }

                    let payload: BackupPayload = try await MainActor.run {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        return try decoder.decode(BackupPayload.self, from: payloadBytes)
                    }

                    progress(0.22, "Validating…")
                    let validation = Self.validate(payload: payload, mode: mode)
                    if !validation.errors.isEmpty {
                        let displayedErrors = validation.errors.prefix(3).joined(separator: "; ")
                        let errorMessage = "Validation errors: \(displayedErrors). Total errors: \(validation.errors.count)"
                        throw NSError(domain: "BackupService", code: 2000, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    }
                    warnings.append(contentsOf: validation.warnings)

                    progress(0.30, mode == .replace ? "Replacing data…" : "Merging data…")
                    try await Self.performRestore(using: modelContext, payload: payload, mode: mode, progress: progress)

                    // Apply preferences from backup with warnings
                    var prefsWarnings: [String] = []
                    await Self.applyPreferences(payload.preferences, warnings: &prefsWarnings)
                    warnings.append(contentsOf: prefsWarnings)

                    let summary = BackupOperationSummary(
                        fileName: url.lastPathComponent,
                        formatVersion: envInfo.formatVersion,
                        encryptUsed: envInfo.encryptedPayload != nil,
                        createdAt: envInfo.createdAt,
                        entityCounts: envInfo.entityCounts,
                        warnings: warnings
                    )

                    progress(1.0, "Restore complete")
                    continuation.resume(returning: summary)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Build Payload from SwiftData
    @MainActor
    private static func buildPayload(using ctx: ModelContext) async throws -> BackupPayload {
        // Fetch all entities and map to DTOs. Only include fields that are data-only.
        func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            var fd = FetchDescriptor<T>()
            fd.includePendingChanges = false
            return try ctx.fetch(fd)
        }

        // Items
        let items: [ItemDTO] = (try? fetch(Item.self))?.map { ItemDTO(id: UUID(), timestamp: $0.timestamp) } ?? []

        // Students
        let students: [StudentDTO] = (try? fetch(Student.self))?.map { s in
            StudentDTO(
                id: s.id,
                firstName: s.firstName,
                lastName: s.lastName,
                birthday: s.birthday,
                dateStarted: s.dateStarted,
                level: StudentDTO.Level(rawValue: s.level.rawValue.lowercased()) ?? .lower,
                nextLessons: s.nextLessons,
                manualOrder: s.manualOrder,
                createdAt: nil,
                updatedAt: nil
            )
        } ?? []

        // Lessons (exclude file bytes; include relative path only)
        let lessons: [LessonDTO] = (try? fetch(Lesson.self))?.map { l in
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
        } ?? []

        // StudentLessons
        let studentLessons: [StudentLessonDTO] = (try? fetch(StudentLesson.self))?.map { sl in
            StudentLessonDTO(
                id: sl.id,
                lessonID: sl.resolvedLessonID,
                studentIDs: sl.resolvedStudentIDs,
                createdAt: sl.createdAt,
                scheduledFor: sl.scheduledFor,
                givenAt: sl.givenAt,
                isPresented: sl.isPresented,
                notes: sl.notes,
                needsPractice: sl.needsPractice,
                needsAnotherPresentation: sl.needsAnotherPresentation,
                followUpWork: sl.followUpWork,
                studentGroupKey: sl.studentGroupKeyPersisted.isEmpty ? nil : sl.studentGroupKeyPersisted
            )
        } ?? []

        // Works
        let works: [WorkDTO] = (try? fetch(WorkModel.self))?.map { w in
            WorkDTO(
                id: w.id,
                title: w.title,
                studentIDs: w.participants.map { $0.studentID },
                workType: w.workType.rawValue,
                studentLessonID: w.studentLessonID,
                notes: w.notes,
                createdAt: w.createdAt,
                completedAt: w.completedAt,
                participants: w.participants.map { WorkParticipantDTO(studentID: $0.studentID, completedAt: $0.completedAt) }
            )
        } ?? []

        // Attendance
        let attendance: [AttendanceRecordDTO] = (try? fetch(AttendanceRecord.self))?.map { a in
            AttendanceRecordDTO(id: a.id, studentID: a.studentID, date: a.date, status: a.status.rawValue, note: a.note)
        } ?? []

        // WorkCompletion
        let workCompletions: [WorkCompletionRecordDTO] = (try? fetch(WorkCompletionRecord.self))?.map { r in
            WorkCompletionRecordDTO(id: r.id, workID: r.workID, studentID: r.studentID, completedAt: r.completedAt, note: r.note)
        } ?? []

        // WorkCheckIn
        let workCheckIns: [WorkCheckInDTO] = (try? fetch(WorkCheckIn.self))?.map { r in
            WorkCheckInDTO(id: r.id, workID: r.workID, date: r.date, status: r.status.rawValue, purpose: r.purpose, note: r.note)
        } ?? []

        // WorkContracts
        let workContracts: [WorkContractDTO] = (try? fetch(WorkContract.self))?.map { c in
            WorkContractDTO(
                id: c.id,
                studentID: c.studentID,
                lessonID: c.lessonID,
                presentationID: c.presentationID,
                status: c.status.rawValue,
                scheduledDate: c.scheduledDate,
                createdAt: c.createdAt,
                completedAt: c.completedAt,
                kind: c.kind?.rawValue,
                scheduledReason: c.scheduledReason?.rawValue,
                scheduledNote: c.scheduledNote,
                completionOutcome: c.completionOutcome?.rawValue,
                completionNote: c.completionNote,
                legacyStudentLessonID: c.legacyStudentLessonID
            )
        } ?? []

        // WorkPlanItems
        let workPlanItems: [WorkPlanItemDTO] = (try? fetch(WorkPlanItem.self))?.map { p in
            WorkPlanItemDTO(id: p.id, workID: p.workID, scheduledDate: p.scheduledDate, reason: p.reason?.rawValue ?? WorkPlanItem.Reason.progressCheck.rawValue, note: p.note)
        } ?? []

        // Notes (standard)
        let notesModels: [Note] = (try? fetch(Note.self)) ?? []
        var notes: [NoteDTO] = []
        for n in notesModels {
            let scopeJSON: String = ((try? Self.encodeToJSONString(n.scope)) ?? (try? Self.encodeToJSONString(NoteScope.all)) ?? "{}")
            notes.append(NoteDTO(id: n.id, createdAt: n.createdAt, updatedAt: n.updatedAt, body: n.body, isPinned: n.isPinned, scope: scopeJSON, lessonID: n.lesson?.id, workID: n.work?.id))
        }

        // ScopedNotes
        let scopedNotes: [ScopedNoteDTO] = (try? fetch(ScopedNote.self))?.map { n in
            ScopedNoteDTO(
                id: n.id,
                createdAt: n.createdAt,
                updatedAt: n.updatedAt,
                body: n.body,
                scope: ((try? Self.encodeToJSONString(n.scope)) ?? (try? Self.encodeToJSONString(ScopedNote.Scope.all)) ?? "{}"),
                legacyFingerprint: n.legacyFingerprint,
                studentLessonID: n.studentLesson?.id,
                workID: n.work?.id,
                presentationID: nil,
                workContractID: nil
            )
        } ?? []

        // Calendar
        let nonSchoolDays: [NonSchoolDayDTO] = (try? fetch(NonSchoolDay.self))?.map { NonSchoolDayDTO(id: $0.id, date: $0.date, reason: $0.reason) } ?? []
        let schoolDayOverrides: [SchoolDayOverrideDTO] = (try? fetch(SchoolDayOverride.self))?.map { SchoolDayOverrideDTO(id: $0.id, date: $0.date, note: $0.note) } ?? []

        // Meetings & community
        let studentMeetings: [StudentMeetingDTO] = (try? fetch(StudentMeeting.self))?.map { StudentMeetingDTO(id: $0.id, studentID: $0.studentID, date: $0.date, completed: $0.completed, reflection: $0.reflection, focus: $0.focus, requests: $0.requests, guideNotes: $0.guideNotes) } ?? []

        let presentations: [PresentationDTO] = (try? fetch(Presentation.self))?.map { p in
            PresentationDTO(id: p.id, createdAt: p.createdAt, presentedAt: p.presentedAt, lessonID: p.lessonID, studentIDs: p.studentIDs, legacyStudentLessonID: p.legacyStudentLessonID, lessonTitleSnapshot: p.lessonTitleSnapshot, lessonSubtitleSnapshot: p.lessonSubtitleSnapshot)
        } ?? []

        let communityTopics: [CommunityTopicDTO] = (try? fetch(CommunityTopic.self))?.map { CommunityTopicDTO(id: $0.id, title: $0.title, issueDescription: $0.issueDescription, createdAt: $0.createdAt, addressedDate: $0.addressedDate, resolution: $0.resolution, raisedBy: $0.raisedBy, tags: $0.tags) } ?? []

        let proposedSolutions: [ProposedSolutionDTO] = (try? fetch(ProposedSolution.self))?.map { ProposedSolutionDTO(id: $0.id, topicID: $0.topic?.id, title: $0.title, details: $0.details, proposedBy: $0.proposedBy, createdAt: $0.createdAt, isAdopted: $0.isAdopted) } ?? []

        let meetingNotes: [MeetingNoteDTO] = (try? fetch(MeetingNote.self))?.map { MeetingNoteDTO(id: $0.id, topicID: $0.topic?.id, speaker: $0.speaker, content: $0.content, createdAt: $0.createdAt) } ?? []

        // CommunityAttachment metadata only (no data bytes)
        let communityAttachments: [CommunityAttachmentDTO] = (try? fetch(CommunityAttachment.self))?.map { CommunityAttachmentDTO(id: $0.id, topicID: $0.topic?.id, filename: $0.filename, kind: $0.kind.rawValue, createdAt: $0.createdAt) } ?? []

        // Preferences (typed capture)
        let preferences = Self.capturePreferences()

        return BackupPayload(
            items: items,
            students: students,
            lessons: lessons,
            studentLessons: studentLessons,
            works: works,
            attendance: attendance,
            workCompletions: workCompletions,
            workCheckIns: workCheckIns,
            workContracts: workContracts,
            workPlanItems: workPlanItems,
            scopedNotes: scopedNotes,
            notes: notes,
            nonSchoolDays: nonSchoolDays,
            schoolDayOverrides: schoolDayOverrides,
            studentMeetings: studentMeetings,
            presentations: presentations,
            communityTopics: communityTopics,
            proposedSolutions: proposedSolutions,
            meetingNotes: meetingNotes,
            communityAttachments: communityAttachments,
            preferences: preferences
        )
    }

    // MARK: - Restore
    @MainActor
    private static func performRestore(using ctx: ModelContext, payload: BackupPayload, mode: RestoreMode, progress: @Sendable (Double, String) -> Void) async throws {
        // Replace mode: delete all then insert
        if mode == .replace {
            try deleteAll(using: ctx)
        }

        // Insert or upsert in a deterministic order to satisfy relationships
        // 1) Lessons, Students
        try upsertLessons(payload.lessons, in: ctx)
        try upsertStudents(payload.students, in: ctx)

        // 2) StudentLessons
        try upsertStudentLessons(payload.studentLessons, in: ctx)

        // 3) Works and related
        try upsertWorks(payload.works, in: ctx)
        try upsertWorkContracts(payload.workContracts, in: ctx)
        try upsertWorkPlanItems(payload.workPlanItems, in: ctx)
        try upsertWorkCheckIns(payload.workCheckIns, in: ctx)
        try upsertWorkCompletions(payload.workCompletions, in: ctx)

        // 4) Attendance
        try upsertAttendance(payload.attendance, in: ctx)

        // 5) Meetings & community
        try upsertStudentMeetings(payload.studentMeetings, in: ctx)
        try upsertPresentations(payload.presentations, in: ctx)
        try upsertCommunityTopics(payload.communityTopics, in: ctx)
        try upsertProposedSolutions(payload.proposedSolutions, in: ctx)
        try upsertMeetingNotes(payload.meetingNotes, in: ctx)
        try upsertCommunityAttachments(payload.communityAttachments, in: ctx)

        // 6) Notes
        try await upsertNotes(payload.notes, in: ctx)
        try upsertScopedNotes(payload.scopedNotes, in: ctx)

        // 7) Calendar
        try upsertNonSchoolDays(payload.nonSchoolDays, in: ctx)
        try upsertSchoolDayOverrides(payload.schoolDayOverrides, in: ctx)

        // 8) Items (ephemeral)
        try upsertItems(payload.items, in: ctx)

        // Preferences applied separately

        try ctx.save()
    }

    // MARK: - Validation

    private static func validate(payload: BackupPayload, mode: RestoreMode) -> BackupValidationResult {
        var result = BackupValidationResult()

        // Helper to check duplicates in array of DTOs by id
        func checkDuplicates<T, ID: Hashable>(_ array: [T], entityName: String, id: (T) -> ID) {
            var seen = Set<ID>()
            for item in array {
                let theID = id(item)
                if seen.contains(theID) {
                    result.errors.append("Duplicate ID in \(entityName): \(theID)")
                } else {
                    seen.insert(theID)
                }
            }
        }

        // Check duplicates in all main entities that have ID
        checkDuplicates(payload.lessons, entityName: "Lesson", id: { $0.id })
        checkDuplicates(payload.students, entityName: "Student", id: { $0.id })
        checkDuplicates(payload.studentLessons, entityName: "StudentLesson", id: { $0.id })
        checkDuplicates(payload.works, entityName: "Work", id: { $0.id })
        checkDuplicates(payload.attendance, entityName: "Attendance", id: { $0.id })
        checkDuplicates(payload.workCompletions, entityName: "WorkCompletionRecord", id: { $0.id })
        checkDuplicates(payload.workCheckIns, entityName: "WorkCheckIn", id: { $0.id })
        checkDuplicates(payload.workContracts, entityName: "WorkContract", id: { $0.id })
        checkDuplicates(payload.workPlanItems, entityName: "WorkPlanItem", id: { $0.id })
        checkDuplicates(payload.scopedNotes, entityName: "ScopedNote", id: { $0.id })
        checkDuplicates(payload.notes, entityName: "Note", id: { $0.id })
        checkDuplicates(payload.nonSchoolDays, entityName: "NonSchoolDay", id: { $0.id })
        checkDuplicates(payload.schoolDayOverrides, entityName: "SchoolDayOverride", id: { $0.id })
        checkDuplicates(payload.studentMeetings, entityName: "StudentMeeting", id: { $0.id })
        checkDuplicates(payload.presentations, entityName: "Presentation", id: { $0.id })
        checkDuplicates(payload.communityTopics, entityName: "CommunityTopic", id: { $0.id })
        checkDuplicates(payload.proposedSolutions, entityName: "ProposedSolution", id: { $0.id })
        checkDuplicates(payload.meetingNotes, entityName: "MeetingNote", id: { $0.id })
        checkDuplicates(payload.communityAttachments, entityName: "CommunityAttachment", id: { $0.id })

        // Build sets of IDs for reference resolution
        let lessonIDs = Set(payload.lessons.map { $0.id })
        let studentIDs = Set(payload.students.map { $0.id })
        let studentLessonIDs = Set(payload.studentLessons.map { $0.id })
        let workIDs = Set(payload.works.map { $0.id })
        let communityTopicIDs = Set(payload.communityTopics.map { $0.id })

        // StudentLesson must include at least one student
        for sl in payload.studentLessons {
            if sl.studentIDs.isEmpty {
                if mode == .replace {
                    result.errors.append("StudentLesson \(sl.id) has zero students")
                } else {
                    result.warnings.append("StudentLesson \(sl.id) has zero students; will be skipped during merge")
                }
            }
        }

        // Validate relationships and references
        // StudentLesson.lessonID must exist
        for sl in payload.studentLessons {
            if !lessonIDs.contains(sl.lessonID) {
                if mode == .replace {
                    result.errors.append("StudentLesson references missing Lesson id \(sl.lessonID)")
                } else {
                    result.warnings.append("StudentLesson \(sl.id) references missing Lesson; left as-is")
                }
            }
        }

        // Work.studentLessonID must exist if not nil
        for w in payload.works {
            if let slID = w.studentLessonID, !studentLessonIDs.contains(slID) {
                if mode == .replace {
                    result.errors.append("Work references missing StudentLesson id \(slID)")
                } else {
                    result.warnings.append("Work \(w.id) references missing StudentLesson; left as-is")
                }
            }
            // WorkParticipant.studentID must exist
            for p in w.participants {
                if !studentIDs.contains(p.studentID) {
                    if mode == .replace {
                        result.errors.append("WorkParticipant in Work \(w.id) references missing Student id \(p.studentID)")
                    } else {
                        result.warnings.append("WorkParticipant in Work \(w.id) references missing Student; left as-is")
                    }
                }
            }
        }

        // WorkCheckIn.workID must exist
        for ci in payload.workCheckIns {
            if !workIDs.contains(ci.workID) {
                if mode == .replace {
                    result.errors.append("WorkCheckIn references missing Work id \(ci.workID)")
                } else {
                    result.warnings.append("WorkCheckIn \(ci.id) references missing Work; left as-is")
                }
            }
        }

        // Notes.lessonID and Notes.workID if present must exist
        for n in payload.notes {
            if let lessonID = n.lessonID, !lessonIDs.contains(lessonID) {
                if mode == .replace {
                    result.errors.append("Note \(n.id) references missing Lesson id \(lessonID)")
                } else {
                    result.warnings.append("Note \(n.id) references missing Lesson; left as-is")
                }
            }
            if let workID = n.workID, !workIDs.contains(workID) {
                if mode == .replace {
                    result.errors.append("Note \(n.id) references missing Work id \(workID)")
                } else {
                    result.warnings.append("Note \(n.id) references missing Work; left as-is")
                }
            }
        }

        // ScopedNote relationships
        let presentationIDs = Set(payload.presentations.map { $0.id })
        let workContractIDs = Set(payload.workContracts.map { $0.id })

        for sn in payload.scopedNotes {
            if let slID = sn.studentLessonID, !studentLessonIDs.contains(slID) {
                if mode == .replace {
                    result.errors.append("ScopedNote \(sn.id) references missing StudentLesson id \(slID)")
                } else {
                    result.warnings.append("ScopedNote \(sn.id) references missing StudentLesson; left as-is")
                }
            }
            if let wID = sn.workID, !workIDs.contains(wID) {
                if mode == .replace {
                    result.errors.append("ScopedNote \(sn.id) references missing Work id \(wID)")
                } else {
                    result.warnings.append("ScopedNote \(sn.id) references missing Work; left as-is")
                }
            }
            if let pID = sn.presentationID, !presentationIDs.contains(pID) {
                if mode == .replace {
                    result.errors.append("ScopedNote \(sn.id) references missing Presentation id \(pID)")
                } else {
                    result.warnings.append("ScopedNote \(sn.id) references missing Presentation; left as-is")
                }
            }
            if let cID = sn.workContractID, !workContractIDs.contains(cID) {
                if mode == .replace {
                    result.errors.append("ScopedNote \(sn.id) references missing WorkContract id \(cID)")
                } else {
                    result.warnings.append("ScopedNote \(sn.id) references missing WorkContract; left as-is")
                }
            }
        }

        // ProposedSolution.topicID must exist if present
        for ps in payload.proposedSolutions {
            if let topicID = ps.topicID, !communityTopicIDs.contains(topicID) {
                if mode == .replace {
                    result.errors.append("ProposedSolution \(ps.id) references missing CommunityTopic id \(topicID)")
                } else {
                    result.warnings.append("ProposedSolution \(ps.id) references missing CommunityTopic; left as-is")
                }
            }
        }

        // MeetingNote.topicID must exist if present
        for mn in payload.meetingNotes {
            if let topicID = mn.topicID, !communityTopicIDs.contains(topicID) {
                if mode == .replace {
                    result.errors.append("MeetingNote \(mn.id) references missing CommunityTopic id \(topicID)")
                } else {
                    result.warnings.append("MeetingNote \(mn.id) references missing CommunityTopic; left as-is")
                }
            }
        }

        // CommunityAttachment.topicID must exist if present
        for ca in payload.communityAttachments {
            if let topicID = ca.topicID, !communityTopicIDs.contains(topicID) {
                if mode == .replace {
                    result.errors.append("CommunityAttachment \(ca.id) references missing CommunityTopic id \(topicID)")
                } else {
                    result.warnings.append("CommunityAttachment \(ca.id) references missing CommunityTopic; left as-is")
                }
            }
        }

        return result
    }

    // MARK: - Typed Preferences Handling

    @MainActor
    private static func capturePreferences() -> PreferencesDTO {
        var values: [String: PreferenceValueDTO] = [:]
        let defaults = UserDefaults.standard

        // PreferenceRegistry replaced local PreferenceSchema
        for (key, pref) in PreferenceRegistry.byKey {
            switch pref.type {
            case .bool:
                if let v = defaults.object(forKey: key) as? Bool {
                    values[key] = .bool(v)
                }
            case .int:
                if let v = defaults.object(forKey: key) as? Int {
                    values[key] = .int(v)
                } else if let v = defaults.object(forKey: key) as? NSNumber {
                    values[key] = .int(v.intValue)
                }
            case .double:
                if let v = defaults.object(forKey: key) as? Double {
                    values[key] = .double(v)
                } else if let v = defaults.object(forKey: key) as? NSNumber {
                    values[key] = .double(v.doubleValue)
                }
            case .string:
                if let v = defaults.object(forKey: key) as? String {
                    values[key] = .string(v)
                }
            case .data:
                if let v = defaults.object(forKey: key) as? Data {
                    values[key] = .data(v)
                }
            case .date:
                if let v = defaults.object(forKey: key) as? Date {
                    values[key] = .date(v)
                }
            }
        }

        // Attendance lock states dynamic keys
        let lockPrefix = "Attendance.locked."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(lockPrefix) {
            if let boolValue = value as? Bool, boolValue == true {
                values[key] = .bool(true)
            }
        }

        return PreferencesDTO(values: values)
    }

    @MainActor
    private static func applyPreferences(_ prefs: PreferencesDTO, warnings: inout [String]) {
        let defaults = UserDefaults.standard
        for (key, value) in prefs.values {
            if let pref = PreferenceRegistry.byKey[key] {
                switch value {
                case .bool(let boolVal):
                    if pref.type == .bool {
                        defaults.set(boolVal, forKey: key)
                    } else {
                        warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                    }
                case .int(let intVal):
                    if pref.type == .int {
                        defaults.set(intVal, forKey: key)
                    } else {
                        warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                    }
                case .double(let doubleVal):
                    if pref.type == .double {
                        defaults.set(doubleVal, forKey: key)
                    } else {
                        warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                    }
                case .string(let strVal):
                    if pref.type == .string {
                        defaults.set(strVal, forKey: key)
                    } else if pref.type == .bool {
                        if let boolVal = stringToBool(strVal) {
                            defaults.set(boolVal, forKey: key)
                        } else {
                            warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                        }
                    } else if pref.type == .int {
                        if let intVal = Int(strVal) {
                            defaults.set(intVal, forKey: key)
                        } else {
                            warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                        }
                    } else if pref.type == .double {
                        if let doubleVal = Double(strVal) {
                            defaults.set(doubleVal, forKey: key)
                        } else {
                            warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                        }
                    } else if pref.type == .date {
                        if let dateVal = ISO8601DateFormatter().date(from: strVal) {
                            defaults.set(dateVal, forKey: key)
                        } else {
                            warnings.append("Preference '\(key)' skipped: expected ISO8601 Date")
                        }
                    } else if pref.type == .data {
                        if let dataVal = Data(base64Encoded: strVal) {
                            defaults.set(dataVal, forKey: key)
                        } else {
                            warnings.append("Preference '\(key)' skipped: expected Base64 Data")
                        }
                    } else {
                        warnings.append("Preference '\(key)' skipped: type mismatch")
                    }
                case .data(let dataVal):
                    if pref.type == .data {
                        defaults.set(dataVal, forKey: key)
                    } else {
                        warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                    }
                case .date(let dateVal):
                    if pref.type == .date {
                        defaults.set(dateVal, forKey: key)
                    } else {
                        warnings.append("Preference '\(key)' skipped: expected \(pref.type)")
                    }
                }
            } else if key.hasPrefix("Attendance.locked.") {
                // Dynamic keys, expected bool true only
                switch value {
                case .bool(true):
                    defaults.set(true, forKey: key)
                default:
                    warnings.append("Preference '\(key)' skipped: expected Bool true")
                }
            } else {
                // Unknown keys, write based on PreferenceValueDTO type
                switch value {
                case .bool(let boolVal):
                    defaults.set(boolVal, forKey: key)
                case .int(let intVal):
                    defaults.set(intVal, forKey: key)
                case .double(let doubleVal):
                    defaults.set(doubleVal, forKey: key)
                case .string(let strVal):
                    defaults.set(strVal, forKey: key)
                case .data(let dataVal):
                    defaults.set(dataVal, forKey: key)
                case .date(let dateVal):
                    defaults.set(dateVal, forKey: key)
                }
            }
        }
        defaults.synchronize()
    }

    private static func stringToBool(_ str: String) -> Bool? {
        let lowered = str.lowercased()
        switch lowered {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    // MARK: - Upsert helpers
    @MainActor
    private static func upsertItems(_ dtos: [ItemDTO], in ctx: ModelContext) throws {
        // Items have no stable identity in current model; insert as new
        for dto in dtos { ctx.insert(Item(timestamp: dto.timestamp)) }
    }

    @MainActor
    private static func upsertStudents(_ dtos: [StudentDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<Student>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let s = map[d.id] {
                s.firstName = d.firstName; s.lastName = d.lastName; s.birthday = d.birthday; s.dateStarted = d.dateStarted; s.level = (d.level == .upper ? .upper : .lower); s.nextLessons = d.nextLessons; s.manualOrder = d.manualOrder
            } else {
                let s = Student(id: d.id, firstName: d.firstName, lastName: d.lastName, birthday: d.birthday, level: d.level == .upper ? .upper : .lower, dateStarted: d.dateStarted, nextLessons: d.nextLessons, manualOrder: d.manualOrder)
                ctx.insert(s)
            }
        }
    }

    @MainActor
    private static func upsertLessons(_ dtos: [LessonDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<Lesson>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let l = map[d.id] {
                l.name = d.name; l.subject = d.subject; l.group = d.group; l.orderInGroup = d.orderInGroup; l.subheading = d.subheading; l.writeUp = d.writeUp; l.pagesFileRelativePath = d.pagesFileRelativePath
            } else {
                let l = Lesson(id: d.id, name: d.name, subject: d.subject, group: d.group, subheading: d.subheading, writeUp: d.writeUp, pagesFileBookmark: nil, pagesFileRelativePath: d.pagesFileRelativePath)
                l.orderInGroup = d.orderInGroup
                ctx.insert(l)
            }
        }
    }

    @MainActor
    private static func upsertStudentLessons(_ dtos: [StudentLessonDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<StudentLesson>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            // Skip invalid zero-student lessons
            if d.studentIDs.isEmpty { continue }
            if let obj = map[d.id] {
                obj.lessonID = d.lessonID; obj.studentIDs = d.studentIDs; obj.createdAt = d.createdAt; obj.scheduledFor = d.scheduledFor; obj.givenAt = d.givenAt; obj.isPresented = d.isPresented; obj.notes = d.notes; obj.needsPractice = d.needsPractice; obj.needsAnotherPresentation = d.needsAnotherPresentation; obj.followUpWork = d.followUpWork; if let g = d.studentGroupKey { obj.studentGroupKeyPersisted = g }
            } else {
                let obj = StudentLesson(id: d.id, lessonID: d.lessonID, studentIDs: d.studentIDs, createdAt: d.createdAt, scheduledFor: d.scheduledFor, givenAt: d.givenAt, notes: d.notes, needsPractice: d.needsPractice, needsAnotherPresentation: d.needsAnotherPresentation, followUpWork: d.followUpWork)
                obj.isPresented = d.isPresented
                if let g = d.studentGroupKey { obj.studentGroupKeyPersisted = g }
                ctx.insert(obj)
            }
        }
    }

    @MainActor
    private static func upsertWorks(_ dtos: [WorkDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<WorkModel>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let w = map[d.id] {
                w.title = d.title; w.workType = WorkModel.WorkType(rawValue: d.workType) ?? .practice; w.studentLessonID = d.studentLessonID; w.notes = d.notes; w.createdAt = d.createdAt; w.completedAt = d.completedAt
                // Update participants
                w.participants = d.participants.map { WorkParticipantEntity(studentID: $0.studentID, completedAt: $0.completedAt) }
                for p in w.participants { p.work = w }
            } else {
                let participants = d.participants.map { WorkParticipantEntity(studentID: $0.studentID, completedAt: $0.completedAt) }
                let w = WorkModel(id: d.id, title: d.title, workType: WorkModel.WorkType(rawValue: d.workType) ?? .practice, studentLessonID: d.studentLessonID, notes: d.notes, createdAt: d.createdAt, completedAt: d.completedAt, participants: participants)
                for p in w.participants { p.work = w }
                ctx.insert(w)
            }
        }
    }

    @MainActor
    private static func upsertWorkContracts(_ dtos: [WorkContractDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<WorkContract>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let c = map[d.id] {
                c.studentID = d.studentID; c.lessonID = d.lessonID; c.presentationID = d.presentationID; c.status = WorkStatus(rawValue: d.status) ?? .active; c.scheduledDate = d.scheduledDate; if let created = d.createdAt { c.createdAt = created }; c.completedAt = d.completedAt; c.kind = d.kind.flatMap { WorkKind(rawValue: $0) }; c.scheduledReason = d.scheduledReason.flatMap { ScheduledReason(rawValue: $0) }; c.scheduledNote = d.scheduledNote; c.completionOutcome = d.completionOutcome.flatMap { CompletionOutcome(rawValue: $0) }; c.completionNote = d.completionNote; c.legacyStudentLessonID = d.legacyStudentLessonID
            } else {
                let c = WorkContract(studentID: d.studentID, lessonID: d.lessonID, presentationID: d.presentationID, status: WorkStatus(rawValue: d.status) ?? .active)
                c.id = d.id; if let created = d.createdAt { c.createdAt = created }; c.scheduledDate = d.scheduledDate; c.completedAt = d.completedAt; c.kind = d.kind.flatMap { WorkKind(rawValue: $0) }; c.scheduledReason = d.scheduledReason.flatMap { ScheduledReason(rawValue: $0) }; c.scheduledNote = d.scheduledNote; c.completionOutcome = d.completionOutcome.flatMap { CompletionOutcome(rawValue: $0) }; c.completionNote = d.completionNote; c.legacyStudentLessonID = d.legacyStudentLessonID
                ctx.insert(c)
            }
        }
    }

    @MainActor
    private static func upsertWorkPlanItems(_ dtos: [WorkPlanItemDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<WorkPlanItem>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let p = map[d.id] {
                p.workID = d.workID; p.scheduledDate = d.scheduledDate; p.reason = WorkPlanItem.Reason(rawValue: d.reason) ?? .progressCheck; p.note = d.note
            } else {
                let p = WorkPlanItem(workID: d.workID, scheduledDate: d.scheduledDate, reason: WorkPlanItem.Reason(rawValue: d.reason) ?? .progressCheck, note: d.note); p.id = d.id; ctx.insert(p)
            }
        }
    }

    @MainActor
    private static func upsertWorkCheckIns(_ dtos: [WorkCheckInDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<WorkCheckIn>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        // Build works map for relationship wiring
        let works = try ctx.fetch(FetchDescriptor<WorkModel>())
        let worksByID = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0) })
        for d in dtos {
            if let ci = map[d.id] {
                ci.workID = d.workID; ci.date = d.date; ci.status = WorkCheckInStatus(rawValue: d.status) ?? .scheduled; ci.purpose = d.purpose; ci.note = d.note; ci.work = worksByID[d.workID]
            } else {
                let ci = WorkCheckIn(id: d.id, workID: d.workID, date: d.date, status: WorkCheckInStatus(rawValue: d.status) ?? .scheduled, purpose: d.purpose, note: d.note, work: worksByID[d.workID]); ctx.insert(ci)
            }
        }
    }

    @MainActor
    private static func upsertWorkCompletions(_ dtos: [WorkCompletionRecordDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<WorkCompletionRecord>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let r = map[d.id] { r.workID = d.workID; r.studentID = d.studentID; r.completedAt = d.completedAt; r.note = d.note }
            else { let r = WorkCompletionRecord(id: d.id, workID: d.workID, studentID: d.studentID, completedAt: d.completedAt, note: d.note); ctx.insert(r) }
        }
    }

    @MainActor
    private static func upsertAttendance(_ dtos: [AttendanceRecordDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<AttendanceRecord>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos {
            if let a = map[d.id] { a.studentID = d.studentID; a.date = d.date; a.status = AttendanceStatus(rawValue: d.status) ?? .unmarked; a.note = d.note }
            else { let a = AttendanceRecord(id: d.id, studentID: d.studentID, date: d.date, status: AttendanceStatus(rawValue: d.status) ?? .unmarked, note: d.note); ctx.insert(a) }
        }
    }

    @MainActor
    private static func upsertNotes(_ dtos: [NoteDTO], in ctx: ModelContext) async throws {
        let existing = try ctx.fetch(FetchDescriptor<Note>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let lessons = try ctx.fetch(FetchDescriptor<Lesson>())
        let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        let works = try ctx.fetch(FetchDescriptor<WorkModel>())
        let worksByID = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0) })
        for d in dtos {
            let scopeValue = Self.decodeFromJSONString(d.scope, as: NoteScope.self) ?? .all
            if let n = map[d.id] {
                n.createdAt = d.createdAt; n.updatedAt = d.updatedAt; n.body = d.body; n.isPinned = d.isPinned
                n.scope = scopeValue
                n.lesson = d.lessonID.flatMap { lessonsByID[$0] }
                n.work = d.workID.flatMap { worksByID[$0] }
            } else {
                let newNote = Note(id: d.id, createdAt: d.createdAt, updatedAt: d.updatedAt, body: d.body, scope: scopeValue, isPinned: d.isPinned, lesson: d.lessonID.flatMap { lessonsByID[$0] }, work: d.workID.flatMap { worksByID[$0] })
                ctx.insert(newNote)
            }
        }
    }

    @MainActor
    private static func upsertScopedNotes(_ dtos: [ScopedNoteDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<ScopedNote>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let sls = try ctx.fetch(FetchDescriptor<StudentLesson>())
        let slByID = Dictionary(uniqueKeysWithValues: sls.map { ($0.id, $0) })
        let works = try ctx.fetch(FetchDescriptor<WorkModel>())
        let workByID = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0) })
        // Removed fetching contracts and presentations per instructions
        for d in dtos {
            let scopeValue = Self.decodeFromJSONString(d.scope, as: ScopedNote.Scope.self) ?? .all
            if let n = map[d.id] {
                n.createdAt = d.createdAt; n.updatedAt = d.updatedAt; n.body = d.body; n.scope = scopeValue; n.legacyFingerprint = d.legacyFingerprint; n.studentLesson = d.studentLessonID.flatMap { slByID[$0] }; n.work = d.workID.flatMap { workByID[$0] }; n.presentation = nil; n.workContract = nil
            } else {
                let n = ScopedNote(id: d.id, createdAt: d.createdAt, updatedAt: d.updatedAt, body: d.body, scope: scopeValue, legacyFingerprint: d.legacyFingerprint, studentLesson: d.studentLessonID.flatMap { slByID[$0] }, work: d.workID.flatMap { workByID[$0] }, presentation: nil, workContract: nil); ctx.insert(n)
            }
        }
    }

    @MainActor
    private static func upsertNonSchoolDays(_ dtos: [NonSchoolDayDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<NonSchoolDay>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos { if let x = map[d.id] { x.date = d.date; x.reason = d.reason } else { let x = NonSchoolDay(id: d.id, date: d.date, reason: d.reason); ctx.insert(x) } }
    }

    @MainActor
    private static func upsertSchoolDayOverrides(_ dtos: [SchoolDayOverrideDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<SchoolDayOverride>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos { if let x = map[d.id] { x.date = d.date; x.note = d.note } else { let x = SchoolDayOverride(id: d.id, date: d.date, note: d.note); ctx.insert(x) } }
    }

    @MainActor
    private static func upsertStudentMeetings(_ dtos: [StudentMeetingDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<StudentMeeting>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos { if let m = map[d.id] { m.studentID = d.studentID; m.date = d.date; m.completed = d.completed; m.reflection = d.reflection; m.focus = d.focus; m.requests = d.requests; m.guideNotes = d.guideNotes } else { let m = StudentMeeting(id: d.id, studentID: d.studentID, date: d.date, completed: d.completed, reflection: d.reflection, focus: d.focus, requests: d.requests, guideNotes: d.guideNotes); ctx.insert(m) } }
    }

    @MainActor
    private static func upsertPresentations(_ dtos: [PresentationDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<Presentation>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos { if let p = map[d.id] { p.createdAt = d.createdAt; p.presentedAt = d.presentedAt; p.lessonID = d.lessonID; p.studentIDs = d.studentIDs; p.legacyStudentLessonID = d.legacyStudentLessonID; p.lessonTitleSnapshot = d.lessonTitleSnapshot; p.lessonSubtitleSnapshot = d.lessonSubtitleSnapshot } else { let p = Presentation(id: d.id, createdAt: d.createdAt, presentedAt: d.presentedAt, lessonID: d.lessonID, studentIDs: d.studentIDs, legacyStudentLessonID: d.legacyStudentLessonID, lessonTitleSnapshot: d.lessonTitleSnapshot, lessonSubtitleSnapshot: d.lessonSubtitleSnapshot); ctx.insert(p) } }
    }

    @MainActor
    private static func upsertCommunityTopics(_ dtos: [CommunityTopicDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<CommunityTopic>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for d in dtos { if let t = map[d.id] { t.title = d.title; t.issueDescription = d.issueDescription; t.createdAt = d.createdAt; t.addressedDate = d.addressedDate; t.resolution = d.resolution; t.raisedBy = d.raisedBy; t.tags = d.tags } else { let t = CommunityTopic(id: d.id, title: d.title, issueDescription: d.issueDescription, createdAt: d.createdAt, addressedDate: d.addressedDate, resolution: d.resolution); t.raisedBy = d.raisedBy; t.tags = d.tags; ctx.insert(t) } }
    }

    @MainActor
    private static func upsertProposedSolutions(_ dtos: [ProposedSolutionDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<ProposedSolution>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let topics = try ctx.fetch(FetchDescriptor<CommunityTopic>())
        let topicsByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        for d in dtos { if let s = map[d.id] { s.topic = d.topicID.flatMap { topicsByID[$0] }; s.title = d.title; s.details = d.details; s.proposedBy = d.proposedBy; s.createdAt = d.createdAt; s.isAdopted = d.isAdopted } else { let s = ProposedSolution(id: d.id, title: d.title, details: d.details, proposedBy: d.proposedBy, createdAt: d.createdAt, isAdopted: d.isAdopted, topic: d.topicID.flatMap { topicsByID[$0] }); ctx.insert(s) } }
    }

    @MainActor
    private static func upsertMeetingNotes(_ dtos: [MeetingNoteDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<MeetingNote>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let topics = try ctx.fetch(FetchDescriptor<CommunityTopic>())
        let topicsByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        for d in dtos { if let n = map[d.id] { n.topic = d.topicID.flatMap { topicsByID[$0] }; n.speaker = d.speaker; n.content = d.content; n.createdAt = d.createdAt } else { let n = MeetingNote(id: d.id, speaker: d.speaker, content: d.content, createdAt: d.createdAt, topic: d.topicID.flatMap { topicsByID[$0] }); ctx.insert(n) } }
    }

    @MainActor
    private static func upsertCommunityAttachments(_ dtos: [CommunityAttachmentDTO], in ctx: ModelContext) throws {
        let existing = try ctx.fetch(FetchDescriptor<CommunityAttachment>())
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let topics = try ctx.fetch(FetchDescriptor<CommunityTopic>())
        let topicsByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        for d in dtos { if let a = map[d.id] { a.topic = d.topicID.flatMap { topicsByID[$0] }; a.filename = d.filename; a.kind = CommunityAttachment.Kind(rawValue: d.kind) ?? .file; a.createdAt = d.createdAt; a.data = nil } else { let a = CommunityAttachment(id: d.id, filename: d.filename, kind: CommunityAttachment.Kind(rawValue: d.kind) ?? .file, data: nil, createdAt: d.createdAt, topic: d.topicID.flatMap { topicsByID[$0] }); ctx.insert(a) } }
    }

    @MainActor
    private static func deleteAll(using ctx: ModelContext) throws {
        // Delete in reverse dependency order
        let types: [any PersistentModel.Type] = [
            CommunityAttachment.self, MeetingNote.self, ProposedSolution.self, CommunityTopic.self,
            Presentation.self, StudentMeeting.self,
            WorkCheckIn.self, WorkCompletionRecord.self, WorkPlanItem.self, WorkContract.self, WorkModel.self,
            ScopedNote.self, Note.self,
            AttendanceRecord.self,
            StudentLesson.self,
            NonSchoolDay.self, SchoolDayOverride.self,
            Lesson.self, Student.self,
            Item.self
        ]
        for t in types {
            try deleteAll(of: t, using: ctx)
        }
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(of type: T.Type, using ctx: ModelContext) throws {
        let objects = try ctx.fetch(FetchDescriptor<T>())
        for o in objects { ctx.delete(o) }
    }

    // MARK: - Utilities
    private static func counts(from payload: BackupPayload) -> [String: Int] {
        return [
            "items": payload.items.count,
            "students": payload.students.count,
            "lessons": payload.lessons.count,
            "studentLessons": payload.studentLessons.count,
            "works": payload.works.count,
            "attendance": payload.attendance.count,
            "workCompletions": payload.workCompletions.count,
            "workCheckIns": payload.workCheckIns.count,
            "workContracts": payload.workContracts.count,
            "workPlanItems": payload.workPlanItems.count,
            "scopedNotes": payload.scopedNotes.count,
            "notes": payload.notes.count,
            "nonSchoolDays": payload.nonSchoolDays.count,
            "schoolDayOverrides": payload.schoolDayOverrides.count,
            "studentMeetings": payload.studentMeetings.count,
            "presentations": payload.presentations.count,
            "communityTopics": payload.communityTopics.count,
            "proposedSolutions": payload.proposedSolutions.count,
            "meetingNotes": payload.meetingNotes.count,
            "communityAttachments": payload.communityAttachments.count
        ]
    }

    private static func appVersion() -> String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    private static func appBuild() -> String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    @MainActor
    private static func deviceString() -> String {
        #if os(macOS)
        // Prefer localizedName when available on macOS
        if let name = (try? ObjCHost.currentLocalizedName()) { return name }
        #endif
        let host = ProcessInfo.processInfo.hostName
        return host.isEmpty ? "Unknown Device" : host
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func obtainKey() throws -> Data {
        let kc = KeychainStore(service: "com.mariastoolbox.backup", account: "backup-key")
        if let data = try kc.get() { return data }
        let new = KeychainStore.generateSymmetricKeyBytes(length: 32)
        try kc.set(new)
        return new
    }

    private static func encryptAESGCM(plaintext: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw NSError(domain: "BackupService", code: 3001, userInfo: [NSLocalizedDescriptionKey: "Encryption failed"]) }
        return combined
    }

    private static func decryptAESGCM(ciphertext: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    private static func atomicWrite(data: Data, to url: URL) throws {
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    // MARK: - JSON Helpers for Preference and Scope Encoding/Decoding
    private static func encodeToJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
    private static func decodeFromJSONString<T: Decodable>(_ string: String, as type: T.Type) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

