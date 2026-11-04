// swiftlint:disable file_length
import CoreData
import Foundation
import OSLog
@testable import CosmicDaybook

// The backup's hand-written restores for the 38 entity types that "Simplify
// round two", Phase 7 moves to `ModelRow`, copied verbatim from a906650c0's
// `Backup/Import/BackupEntityImporter.swift` (the lookups and the shared
// helpers), `+Students`, `+Lessons`, `+Calendar`, `+Projects` and `+Work` (the
// rest are in `LegacyBackupEntityImporter+Misc.swift` and `+Assets.swift`).
// Only the names are changed: the enum is `LegacyBackupEntityImporter` and
// each DTO its `Legacy` copy (`LegacyBackupDTOs.swift`). `importRows` (the
// `ModelRow` types) and the lesson-file merge stay the app's. The legacy
// restore and `BackupSpecOracleTests` hold the table-driven restore to these,
// so do not "fix" or modernise this code: its only job is to be the old code.

// MARK: - Backup/Import/BackupEntityImporter.swift

/// Handles importing entities from backup DTOs into the database.
///
/// This extracts the entity import logic from BackupService for better
/// testability and separation of concerns.
///
/// Domain-specific import methods are organized into extensions:
/// - `LegacyBackupEntityImporter+Students.swift` -- student imports
/// - `LegacyBackupEntityImporter+Lessons.swift` -- lesson imports
/// - `LegacyBackupEntityImporter+Work.swift` -- work imports
/// - `LegacyBackupEntityImporter+Projects.swift` -- project imports
/// - `LegacyBackupEntityImporter+Calendar.swift` -- calendar imports
/// - `LegacyBackupEntityImporter+Todo.swift` -- todo imports
/// - `LegacyBackupEntityImporter+Misc.swift` -- misc entity imports
enum LegacyBackupEntityImporter {
    private static let logger = Logger.backup

    /// Type alias for a function that looks up an already-stored entity by ID.
    ///
    /// Returns the pre-restore record with that ID, or nil when none exists.
    /// Importers populate whichever object comes back — the existing one or a
    /// freshly inserted one — so a merge restore updates records in place
    /// (records absent from the backup are left alone, and so are records
    /// changed here since the backup: `BackupRestoreRun.rows` holds back the
    /// rows whose stored record has a later `modifiedAt`). In replace mode the
    /// store has already been cleared, so the lookup returns nil and every
    /// record is inserted, but for the types a Replace updates in place: the
    /// names people set and the classroom share's records
    /// (`BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames`).
    typealias ExistingLookup<T: NSManagedObject> = (UUID) throws -> T?

    /// Type alias for a function that resolves a relationship target by ID.
    ///
    /// Distinct from `ExistingLookup` on purpose: these callers assign the
    /// result to a relationship, so they need the object — and they're backed by
    /// `BackupEntityIndex.related`, which must see records inserted earlier in
    /// this same restore.
    typealias EntityLookup<T: NSManagedObject> = (UUID) throws -> T?

    // MARK: - Common Helpers

    /// Resolves the pre-restore record for `id`, or nil when it doesn't exist.
    /// A lookup failure is logged and treated as "not found", so the record is
    /// inserted rather than dropped.
    static func existingEntity<T: NSManagedObject>(
        id: UUID,
        existing: ExistingLookup<T>
    ) -> T? {
        do {
            return try existing(id)
        } catch {
            logger.warning("Failed to look up existing entity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Generic helper for importing simple entities with common pattern.
    ///
    /// `entityBuilder` receives the pre-restore record for the DTO's ID (or nil)
    /// and must populate and return either that object or a new one.
    static func importSimpleEntities<DTO, Entity: NSManagedObject>(
        _ dtos: [DTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<Entity>,
        idExtractor: (DTO) -> UUID,
        entityBuilder: (DTO, Entity?) -> Entity
    ) rethrows {
        for dto in dtos {
            let current = existingEntity(id: idExtractor(dto), existing: existing)
            let entity = entityBuilder(dto, current)
            viewContext.insert(entity)
        }
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Students.swift

// MARK: - Students

extension LegacyBackupEntityImporter {

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    static func importStudents(
        _ dtos: [LegacyStudentDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDStudent>
    ) rethrows -> [UUID: CDStudent] {
        var studentsByID: [UUID: CDStudent] = [:]
        for dto in dtos {
            let student = existingEntity(id: dto.id, existing: existing) ?? CDStudent(context: viewContext)
            student.id = dto.id
            student.firstName = dto.firstName
            student.lastName = dto.lastName
            // Older backups fabricated a birthday for students who had none
            // (.distantPast from one transformer). Restore that sentinel as nil
            // rather than a bogus real date. (Backups where the fabricated value
            // was the export-time Date() are indistinguishable from real data.)
            student.birthday = dto.birthday == .distantPast ? nil : dto.birthday
            switch dto.level {
            case .lower: student.level = .lower
            case .upper: student.level = .upper
            case .adolescent: student.level = .adolescent
            }
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.map(\.uuidString) as NSArray
            student.manualOrder = Int64(dto.manualOrder)
            student.nickname = dto.nickname
            if let v = dto.enrollmentStatusRaw { student.enrollmentStatusRaw = v }
            student.dateWithdrawn = dto.dateWithdrawn
            student.previousLevelRaw = dto.previousLevelRaw
            student.dateLastPromoted = dto.dateLastPromoted
            // An older backup (before v40) has none: `BackupFieldsAddedLater`
            // puts the record's own match back.
            student.parentLockerID = dto.parentLockerID
            // An older backup (before v43) has no answer: the child keeps her
            // own, and a new one reads as born by day (the model's default).
            if let v = dto.bornAfterSunset { student.bornAfterSunset = v }
            // Preserve the original modification time (awakeFromInsert stamped "now");
            // older backups lack the field, so those keep the import-time stamp.
            if let v = dto.modifiedAt { student.modifiedAt = v }
            viewContext.insert(student)
            studentsByID[student.id ?? dto.id] = student
        }
        return studentsByID
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Lessons.swift

// MARK: - Lessons

extension LegacyBackupEntityImporter {

    // Imports lessons from DTOs.
    // swiftlint:disable:next cyclomatic_complexity
    static func importLessons(
        _ dtos: [LegacyLessonDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDLesson>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let lesson = current ?? CDLesson(context: viewContext)
            lesson.id = dto.id
            lesson.name = dto.name
            lesson.area = dto.area
            lesson.sequence = dto.sequence
            lesson.orderInSequence = Int64(dto.orderInSequence)
            lesson.section = dto.section
            lesson.writeUp = dto.writeUp
            if let pages = dto.pagesFileRelativePath { lesson.pagesFileRelativePath = pages }
            if let primaryAttachmentID = dto.primaryAttachmentID {
                lesson.primaryAttachmentID = primaryAttachmentID.uuidString
            }
            // Format v9+ fields
            if let v = dto.suggestedFollowUpWork { lesson.suggestedFollowUpWork = v }
            if let v = dto.sourceRaw { lesson.sourceRaw = v }
            if let v = dto.personalKindRaw { lesson.personalKindRaw = v }
            if let v = dto.defaultWorkKindRaw { lesson.defaultWorkKindRaw = v }
            if let v = dto.materials { lesson.materials = v }
            if let v = dto.purpose { lesson.purpose = v }
            if let v = dto.ageRange { lesson.ageRange = v }
            if let v = dto.teacherNotes { lesson.teacherNotes = v }
            if let v = dto.prerequisiteLessonIDs { lesson.prerequisiteLessonIDs = v }
            if let v = dto.relatedLessonIDs { lesson.relatedLessonIDs = v }
            lesson.parshaKey = dto.parshaKey
            lesson.greatLessonRaw = dto.greatLessonRaw
            if let v = dto.lessonFormatRaw { lesson.lessonFormatRaw = v }
            if let v = dto.sortIndex { lesson.sortIndex = Int64(v) }
            lesson.derivedFromLessonID = dto.derivedFromLessonID
            lesson.parentStoryID = dto.parentStoryID
            if let v = dto.requiresPracticeOverride { lesson.requiresPracticeOverride = v }
            if let v = dto.requiresConfirmationOverride { lesson.requiresConfirmationOverride = v }
            // Format v22+ teaching-album link.
            lesson.albumID = dto.albumID
            if let v = dto.albumPageIndex { lesson.albumPageIndex = Int32(v) }
            lesson.albumLessonTitle = dto.albumLessonTitle
            if let v = dto.albumLinkConfidence { lesson.albumLinkConfidence = v }
            // Format v25+ Three-Year View milestone flag.
            if let v = dto.isKeyLesson { lesson.isKeyLesson = v }
            return lesson
        })
    }

    // MARK: - Sample Works

    /// Imports sample works from DTOs.
    static func importSampleWorks(
        _ dtos: [LegacySampleWorkDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSampleWork>,
        lessonCheck: EntityLookup<CDLesson>
    ) rethrows {
        for dto in dtos {
            let sw = existingEntity(id: dto.id, existing: existing) ?? CDSampleWork(context: viewContext)
            sw.id = dto.id
            sw.title = dto.title
            sw.workKindRaw = (WorkKind(rawValue: dto.workKindRaw) ?? .practiceLesson).rawValue
            sw.orderIndex = Int64(dto.orderIndex)
            sw.notes = dto.notes
            sw.createdAt = dto.createdAt
            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        sw.lesson = lesson
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check lesson for sample work: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(sw)
        }
    }

    // MARK: - LessonAssignments

    /// Imports lesson assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The lesson assignment DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existing: Looks up an already-stored a lesson assignment by ID so it is updated in place
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importLessonAssignments(
        _ dtos: [LegacyLessonAssignmentDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDLessonAssignment>,
        lessonCheck: EntityLookup<CDLesson>
    ) rethrows {
        for dto in dtos {
            // Parse state from raw value
            let state = LessonAssignmentState(rawValue: dto.stateRaw) ?? .draft

            // Parse lesson ID
            guard let lessonUUID = UUID(uuidString: dto.lessonID) else { continue }

            // Parse student IDs
            let studentUUIDs = dto.studentIDs.compactMap { UUID(uuidString: $0) }

            let assignment = existingEntity(id: dto.id, existing: existing) ?? CDLessonAssignment(context: viewContext)
            assignment.id = dto.id
            assignment.createdAt = dto.createdAt
            assignment.stateRaw = state.rawValue
            assignment.scheduledFor = dto.scheduledFor
            assignment.presentedAt = dto.presentedAt
            assignment.lessonID = lessonUUID.uuidString
            assignment.studentIDs = studentUUIDs.map(\.uuidString)
            assignment.needsPractice = dto.needsPractice
            assignment.needsAnotherPresentation = dto.needsAnotherPresentation
            assignment.followUpWork = dto.followUpWork
            assignment.notes = dto.notes
            assignment.trackID = dto.trackID
            assignment.trackStepID = dto.trackStepID
            // Rows from before these (v19) have neither: an assignment already
            // here keeps its own, a new one the defaults.
            if let unblocked = dto.manuallyUnblocked { assignment.manuallyUnblocked = unblocked }
            if let confirmed = dto.confirmedStudentIDs { assignment.confirmedStudentIDs = confirmed }

            // Update modifiedAt
            assignment.modifiedAt = dto.modifiedAt

            // Set snapshots
            assignment.lessonTitleSnapshot = dto.lessonTitleSnapshot
            assignment.lessonSectionSnapshot = dto.lessonSectionSnapshot

            // Set migration tracking
            assignment.migratedFromStudentLessonID = dto.migratedFromLegacyID
            assignment.migratedFromPresentationID = dto.migratedFromPresentationID

            // Link to lesson if exists
            do {
                if let lesson = try lessonCheck(lessonUUID) {
                    assignment.lesson = lesson
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check lesson for assignment: \(desc, privacy: .public)")
            }

            viewContext.insert(assignment)
        }
    }

    // MARK: - CDLesson Presentations

    static func importLessonPresentations(
        _ dtos: [LegacyLessonPresentationDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDLessonPresentation>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let lp = current ?? CDLessonPresentation(context: viewContext)
            lp.id = dto.id
            lp.createdAt = dto.createdAt
            lp.studentID = dto.studentID
            lp.lessonID = dto.lessonID
            lp.presentationID = dto.presentationID
            lp.trackID = dto.trackID
            lp.trackStepID = dto.trackStepID
            lp.stateRaw = (LessonPresentationState(rawValue: dto.stateRaw) ?? .presented).rawValue
            lp.presentedAt = dto.presentedAt
            lp.lastObservedAt = dto.lastObservedAt
            lp.masteredAt = dto.masteredAt
            lp.notes = dto.notes
            lp.followUpActionRaw = dto.followUpActionRaw
            lp.followUpReviewAt = dto.followUpReviewAt
            lp.followUpResolvedAt = dto.followUpResolvedAt
            lp.followUpResolutionRaw = dto.followUpResolutionRaw
            lp.followUpUpdatedAt = dto.followUpUpdatedAt
            lp.followUpEvidenceRaw = dto.followUpEvidenceRaw
            lp.followUpNote = dto.followUpNote
            lp.followUpSupportRaw = dto.followUpSupportRaw
            return lp
        })
    }

}

// MARK: - Backup/Import/BackupEntityImporter+Calendar.swift

// MARK: - Calendar & Meetings

extension LegacyBackupEntityImporter {

    // MARK: - CDStudent Meetings

    /// Imports student meetings from DTOs.
    static func importStudentMeetings(
        _ dtos: [LegacyStudentMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDStudentMeeting>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let meeting = current ?? CDStudentMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.studentID = dto.studentID.uuidString
            meeting.date = dto.date
            meeting.completed = dto.completed
            meeting.reflection = dto.reflection
            meeting.focus = dto.focus
            meeting.requests = dto.requests
            meeting.guideNotes = dto.guideNotes
            return meeting
        })
    }

    // MARK: - Attendance Records

    /// Imports attendance records from DTOs.
    static func importAttendanceRecords(
        _ dtos: [LegacyAttendanceRecordDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAttendanceRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let status = AttendanceStatus(
                    rawValue: dto.status
                ) ?? .unmarked
                let record = current ?? CDAttendanceRecord(context: viewContext)
                record.id = dto.id
                record.studentID = dto.studentID.uuidString
                record.date = dto.date
                record.statusRaw = status.rawValue
                // As stored, so Close Arrival's automatic absences
                // ("closeArrival", no typed case) come back as themselves.
                record.absenceReasonRaw = dto.absenceReason ?? AbsenceReason.none.rawValue
                record.recordedBy = dto.recordedBy
                record.recordedByID = dto.recordedByID
                record.recordedByName = dto.recordedByName
                record.modifiedAt = dto.modifiedAt
                record.note = dto.note
                record.markedAt = dto.markedAt
                record.leftAt = dto.leftAt
                record.leavesAt = dto.leavesAt
                record.returnedAt = dto.returnedAt
                record.statusBeforeLeavingRaw = dto.statusBeforeLeavingRaw
                return record
            }
        )
    }

    // MARK: - Calendar Events

    static func importCalendarEvents(
        _ dtos: [LegacyCalendarEventDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDCalendarEvent>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let e = current ?? CDCalendarEvent(context: viewContext)
            e.id = dto.id
            e.title = dto.title
            e.startDate = dto.startDate
            e.endDate = dto.endDate
            e.location = dto.location
            e.notes = dto.notes
            e.isAllDay = dto.isAllDay
            return e
        })
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Projects.swift

// MARK: - Projects

extension LegacyBackupEntityImporter {

    /// Imports projects from DTOs.
    static func importProjects(
        _ dtos: [LegacyProjectDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDProject>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let project = current ?? CDProject(context: viewContext)
                project.id = dto.id
                project.createdAt = dto.createdAt
                project.title = dto.title
                project.bookTitle = dto.bookTitle
                project.memberStudentIDsArray = dto.memberStudentIDs
                // A row from before the flag (v19) has none: a project already here keeps its own.
                if let active = dto.isActive { project.isActive = active }
                // Preserve the original modification time (awakeFromInsert stamped
                // "now"); older backups lack the field and keep the import-time stamp.
                if let v = dto.modifiedAt { project.modifiedAt = v }
                return project
            }
        )
    }

    // MARK: - CDProject Roles

    /// Imports project roles from DTOs.
    static func importProjectRoles(
        _ dtos: [LegacyProjectRoleDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDProjectRole>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let role = current ?? CDProjectRole(context: viewContext)
                role.id = dto.id
                role.createdAt = dto.createdAt
                role.projectID = dto.projectID.uuidString
                role.title = dto.title
                role.summary = dto.summary
                role.instructions = dto.instructions
                return role
            }
        )
    }

    // MARK: - CDProject Sessions

    /// Imports project sessions from DTOs, each linked to its project
    /// (`projectCheck`): the app reaches a project's sessions through the
    /// relationship, not the `projectID` string (bug hunt 2026-11-02, #7).
    static func importProjectSessions(
        _ dtos: [LegacyProjectSessionDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDProjectSession>,
        projectCheck: EntityLookup<CDProject>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let session = current ?? CDProjectSession(context: viewContext)
                session.id = dto.id
                session.createdAt = dto.createdAt
                session.projectID = dto.projectID.uuidString
                do {
                    if let project = try projectCheck(dto.projectID) { session.project = project }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to find the project for a session: \(desc, privacy: .public)")
                }
                session.meetingDate = dto.meetingDate
                session.chapterOrPages = dto.chapterOrPages
                session.agendaItemsJSON = dto.agendaItemsJSON
                session.templateWeekID = dto.templateWeekID?.uuidString
                if let v = dto.assignmentModeRaw { session.assignmentModeRaw = v }
                if let v = dto.minSelections { session.minSelections = Int64(v) }
                if let v = dto.maxSelections { session.maxSelections = Int64(v) }
                return session
            }
        )
    }
}

// MARK: - Backup/Import/BackupEntityImporter+Work.swift

// MARK: - Work

extension LegacyBackupEntityImporter {

    // MARK: - CDWorkModel

    /// Imports CDWorkModel records from DTOs. Must run BEFORE child entities (check-ins, steps, participants).
    static func importWorkModels(
        _ dtos: [LegacyWorkModelDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkModel>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let work = current ?? CDWorkModel(context: viewContext)
                work.id = dto.id
                work.title = dto.title
                work.workTypeRaw = dto.workTypeRaw
                work.kindRaw = dto.kindRaw
                work.studentLessonID = dto.studentLessonID
                work.createdAt = dto.createdAt
                work.completedAt = dto.completedAt
                // Older backups carry `complete` + an outcome; fold them the way the launch repair does.
                work.statusRaw = WorkStatusMigration.mergedStatus(
                    statusRaw: dto.statusRaw, outcomeRaw: dto.completionOutcomeRaw
                ).rawValue
                work.assignedAt = dto.assignedAt
                work.lastTouchedAt = dto.lastTouchedAt
                work.dueAt = dto.dueAt
                work.completionOutcomeRaw = dto.completionOutcomeRaw
                work.studentID = dto.studentID
                work.lessonID = dto.lessonID
                work.presentationID = dto.presentationID
                work.trackID = dto.trackID
                work.trackStepID = dto.trackStepID
                work.scheduledNote = dto.scheduledNote
                work.scheduledReasonRaw = dto.scheduledReasonRaw
                work.sourceContextTypeRaw = dto.sourceContextTypeRaw
                work.sourceContextID = dto.sourceContextID
                work.sampleWorkID = dto.sampleWorkID
                work.checkInStyleRaw = dto.checkInStyleRaw
                work.restingUntil = dto.restingUntil
                return work
            })
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    static func importWorkCompletionRecords(
        _ dtos: [LegacyWorkCompletionRecordDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkCompletionRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let r = current ?? CDWorkCompletionRecord(context: viewContext)
            r.id = dto.id
            r.workID = dto.workID.uuidString
            r.studentID = dto.studentID.uuidString
            r.completedAt = dto.completedAt
            return r
        })
    }

    // MARK: - Work Check-Ins

    static func importWorkCheckIns(
        _ dtos: [LegacyWorkCheckInDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkCheckIn>,
        workCheck: EntityLookup<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            guard let workUUID = UUID(uuidString: dto.workID) else { continue }
            let checkIn = existingEntity(id: dto.id, existing: existing) ?? CDWorkCheckIn(context: viewContext)
            checkIn.id = dto.id
            checkIn.workID = dto.workID
            checkIn.date = dto.date
            checkIn.statusRaw = (WorkCheckInStatus(rawValue: dto.statusRaw) ?? .scheduled).rawValue
            checkIn.purpose = dto.purpose
            // A row from before the flag (v19) has none: a check-in already here keeps its own.
            if let initiated = dto.studentInitiated { checkIn.studentInitiated = initiated }
            // Likewise the duration (schema 23): an older row says nothing about it.
            if let minutes = dto.durationMinutes { checkIn.durationMinutesValue = minutes }
            // Link to work if exists
            do {
                if let work = try workCheck(workUUID) {
                    checkIn.work = work
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check work for check-in: \(desc, privacy: .public)")
            }
            viewContext.insert(checkIn)
        }
    }

    // MARK: - Work Participants

    static func importWorkParticipants(
        _ dtos: [LegacyWorkParticipantEntityDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkParticipantEntity>,
        workCheck: EntityLookup<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            guard UUID(uuidString: dto.studentID) != nil else { continue }
            let participant = existingEntity(id: dto.id, existing: existing) ?? CDWorkParticipantEntity(context: viewContext) // swiftlint:disable:this line_length
            participant.id = dto.id
            participant.studentID = dto.studentID
            participant.completedAt = dto.completedAt
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        participant.work = work
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check work for participant: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(participant)
        }
    }
}
