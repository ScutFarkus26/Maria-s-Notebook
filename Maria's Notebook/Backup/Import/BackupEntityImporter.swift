import Foundation
import SwiftData

/// Handles importing entities from backup DTOs into the database.
///
/// This extracts the entity import logic from BackupService for better
/// testability and separation of concerns.
enum BackupEntityImporter {

    /// Type alias for a function that checks if an entity with a given ID exists
    typealias EntityExistsCheck<T: PersistentModel> = (UUID) throws -> T?

    // MARK: - Common Helpers

    /// Generic helper to check if an entity exists and skip if it does.
    /// Returns true if the entity should be skipped (already exists).
    private static func shouldSkipExisting<T: PersistentModel>(
        id: UUID,
        existingCheck: EntityExistsCheck<T>
    ) -> Bool {
        do {
            return try existingCheck(id) != nil
        } catch {
            print("⚠️ [Backup:\(#function)] Failed to check if entity exists: \(error)")
            return false
        }
    }

    /// Generic helper for importing simple entities with common pattern.
    private static func importSimpleEntities<DTO, Entity: PersistentModel>(
        _ dtos: [DTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Entity>,
        idExtractor: (DTO) -> UUID,
        entityBuilder: (DTO) -> Entity
    ) rethrows {
        for dto in dtos {
            let id = idExtractor(dto)
            if shouldSkipExisting(id: id, existingCheck: existingCheck) { continue }
            let entity = entityBuilder(dto)
            modelContext.insert(entity)
        }
    }

    // MARK: - Students

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    static func importStudents(
        _ dtos: [StudentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Student>
    ) rethrows -> [UUID: Student] {
        var studentsByID: [UUID: Student] = [:]
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing student: \(error)")
                continue
            }
            let student = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: dto.level == .upper ? .upper : .lower
            )
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.uuidStrings
            student.manualOrder = dto.manualOrder
            modelContext.insert(student)
            studentsByID[student.id] = student
        }
        return studentsByID
    }

    // MARK: - Lessons

    /// Imports lessons from DTOs.
    static func importLessons(
        _ dtos: [LessonDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let lesson = Lesson(id: dto.id, name: dto.name, subject: dto.subject, group: dto.group, orderInGroup: dto.orderInGroup, subheading: dto.subheading, writeUp: dto.writeUp)
            if let pages = dto.pagesFileRelativePath { lesson.pagesFileRelativePath = pages }
            return lesson
        }
    }

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    static func importCommunityTopics(
        _ dtos: [CommunityTopicDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let topic = CommunityTopic(id: dto.id, title: dto.title, issueDescription: dto.issueDescription, createdAt: dto.createdAt, addressedDate: dto.addressedDate, resolution: dto.resolution)
            topic.raisedBy = dto.raisedBy
            topic.tags = dto.tags
            return topic
        }
    }

    // MARK: - Student Lessons

    /// Imports student lessons from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The student lesson DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - studentLessonCheck: Function to check if a student lesson already exists
    ///   - lessonCheck: Function to check if the referenced lesson exists
    ///   - studentCheck: Function to look up a student by ID
    static func importStudentLessons(
        _ dtos: [StudentLessonDTO],
        into modelContext: ModelContext,
        studentLessonCheck: EntityExistsCheck<StudentLesson>,
        lessonCheck: EntityExistsCheck<Lesson>,
        studentCheck: EntityExistsCheck<Student>
    ) rethrows {
        for dto in dtos {
            // Skip if lesson doesn't exist
            do {
                guard try lessonCheck(dto.lessonID) != nil else { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check lesson existence: \(error)")
                continue
            }
            // Skip if already exists
            do {
                if try studentLessonCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing student lesson: \(error)")
                continue
            }

            let studentLesson = StudentLessonFactory.makeFromBackup(
                id: dto.id,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs,
                createdAt: dto.createdAt,
                scheduledFor: dto.scheduledFor,
                givenAt: dto.givenAt,
                isPresented: dto.givenAt != nil,
                notes: dto.notes,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork
            )

            var linkedStudents: [Student] = []
            for studentID in dto.studentIDs {
                do {
                    if let student = try studentCheck(studentID) {
                        linkedStudents.append(student)
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check student: \(error)")
                    continue
                }
            }
            if !linkedStudents.isEmpty {
                studentLesson.students = linkedStudents
            }

            modelContext.insert(studentLesson)
        }
    }

    // MARK: - Notes

    /// Imports notes from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The note DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a note already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importNotes(
        _ dtos: [NoteDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Note>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing note: \(error)")
                continue
            }

            let note = Note(
                id: dto.id,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                body: dto.body,
                imagePath: dto.imagePath
            )
            note.isPinned = dto.isPinned

            if let data = dto.scope.data(using: .utf8) {
                do {
                    let scope = try JSONDecoder().decode(NoteScope.self, from: data)
                    note.scope = scope
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to decode note scope: \(error)")
                }
            }

            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        note.lesson = lesson
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check lesson for note: \(error)")
                }
            }

            modelContext.insert(note)
        }
    }

    // MARK: - Non-School Days

    /// Imports non-school days from DTOs.
    static func importNonSchoolDays(_ dtos: [NonSchoolDayDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<NonSchoolDay>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let day = NonSchoolDay(id: dto.id, date: dto.date)
            day.reason = dto.reason
            return day
        }
    }

    // MARK: - School Day Overrides

    /// Imports school day overrides from DTOs.
    static func importSchoolDayOverrides(_ dtos: [SchoolDayOverrideDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<SchoolDayOverride>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let override = SchoolDayOverride(id: dto.id, date: dto.date)
            override.note = dto.note
            return override
        }
    }

    // MARK: - Student Meetings

    /// Imports student meetings from DTOs.
    static func importStudentMeetings(_ dtos: [StudentMeetingDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<StudentMeeting>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let meeting = StudentMeeting(id: dto.id, studentID: dto.studentID, date: dto.date)
            meeting.completed = dto.completed
            meeting.reflection = dto.reflection
            meeting.focus = dto.focus
            meeting.requests = dto.requests
            meeting.guideNotes = dto.guideNotes
            return meeting
        }
    }

    // MARK: - LessonAssignments

    /// Imports lesson assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The lesson assignment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a lesson assignment already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importLessonAssignments(
        _ dtos: [LessonAssignmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonAssignment>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing lesson assignment: \(error)")
                continue
            }

            // Parse state from raw value
            let state = LessonAssignmentState(rawValue: dto.stateRaw) ?? .draft

            // Parse lesson ID
            guard let lessonUUID = UUID(uuidString: dto.lessonID) else { continue }

            // Parse student IDs
            let studentUUIDs = dto.studentIDs.compactMap { UUID(uuidString: $0) }

            let assignment = LessonAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                state: state,
                scheduledFor: dto.scheduledFor,
                presentedAt: dto.presentedAt,
                lessonID: lessonUUID,
                studentIDs: studentUUIDs,
                lesson: nil,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork,
                notes: dto.notes,
                trackID: dto.trackID,
                trackStepID: dto.trackStepID
            )

            // Update modifiedAt
            assignment.modifiedAt = dto.modifiedAt

            // Set snapshots
            assignment.lessonTitleSnapshot = dto.lessonTitleSnapshot
            assignment.lessonSubheadingSnapshot = dto.lessonSubheadingSnapshot

            // Set migration tracking
            assignment.migratedFromStudentLessonID = dto.migratedFromStudentLessonID
            assignment.migratedFromPresentationID = dto.migratedFromPresentationID

            // Link to lesson if exists
            do {
                if let lesson = try lessonCheck(lessonUUID) {
                    assignment.lesson = lesson
                }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check lesson for assignment: \(error)")
            }

            modelContext.insert(assignment)
        }
    }

    // MARK: - Proposed Solutions

    /// Imports proposed solutions from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The proposed solution DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a solution already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importProposedSolutions(
        _ dtos: [ProposedSolutionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProposedSolution>,
        topicCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing proposed solution: \(error)")
                continue
            }

            let solution = ProposedSolution(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                proposedBy: dto.proposedBy,
                createdAt: dto.createdAt,
                isAdopted: dto.isAdopted,
                topic: nil
            )

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        solution.topic = topic
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check topic for proposed solution: \(error)")
                }
            }

            modelContext.insert(solution)
        }
    }

    // MARK: - Community Attachments

    /// Imports community attachments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The community attachment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an attachment already exists
    ///   - topicCheck: Function to look up a community topic by ID
    static func importCommunityAttachments(
        _ dtos: [CommunityAttachmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CommunityAttachment>,
        topicCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing community attachment: \(error)")
                continue
            }

            let attachment = CommunityAttachment(
                id: dto.id,
                filename: dto.filename,
                kind: CommunityAttachment.Kind(rawValue: dto.kind) ?? .file,
                data: nil,
                createdAt: dto.createdAt,
                topic: nil
            )

            if let topicID = dto.topicID {
                do {
                    if let topic = try topicCheck(topicID) {
                        attachment.topic = topic
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check topic for community attachment: \(error)")
                }
            }

            modelContext.insert(attachment)
        }
    }

    // MARK: - Attendance Records

    /// Imports attendance records from DTOs.
    static func importAttendanceRecords(_ dtos: [AttendanceRecordDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<AttendanceRecord>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let absenceReason = dto.absenceReason.flatMap { AbsenceReason(rawValue: $0) } ?? .none
            return AttendanceRecord(id: dto.id, studentID: dto.studentID, date: dto.date, status: AttendanceStatus(rawValue: dto.status) ?? .unmarked, absenceReason: absenceReason, note: dto.note)
        }
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    static func importWorkCompletionRecords(_ dtos: [WorkCompletionRecordDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<WorkCompletionRecord>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            WorkCompletionRecord(id: dto.id, workID: dto.workID, studentID: dto.studentID, completedAt: dto.completedAt, note: dto.note)
        }
    }

    // MARK: - Projects

    /// Imports projects from DTOs.
    static func importProjects(_ dtos: [ProjectDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Project>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            Project(id: dto.id, createdAt: dto.createdAt, title: dto.title, bookTitle: dto.bookTitle, memberStudentIDs: dto.memberStudentIDs)
        }
    }

    // MARK: - Project Roles

    /// Imports project roles from DTOs.
    static func importProjectRoles(_ dtos: [ProjectRoleDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<ProjectRole>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            ProjectRole(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, title: dto.title, summary: dto.summary, instructions: dto.instructions)
        }
    }

    // MARK: - Project Template Weeks

    /// Imports project template weeks from DTOs.
    static func importProjectTemplateWeeks(_ dtos: [ProjectTemplateWeekDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<ProjectTemplateWeek>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            ProjectTemplateWeek(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, weekIndex: dto.weekIndex, readingRange: dto.readingRange, agendaItemsJSON: dto.agendaItemsJSON, linkedLessonIDsJSON: dto.linkedLessonIDsJSON, workInstructions: dto.workInstructions)
        }
    }

    // MARK: - Project Assignment Templates

    /// Imports project assignment templates from DTOs.
    static func importProjectAssignmentTemplates(_ dtos: [ProjectAssignmentTemplateDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<ProjectAssignmentTemplate>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            ProjectAssignmentTemplate(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, title: dto.title, instructions: dto.instructions, isShared: dto.isShared, defaultLinkedLessonID: dto.defaultLinkedLessonID)
        }
    }

    // MARK: - Project Week Role Assignments

    /// Imports project week role assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project week role assignment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an assignment already exists
    ///   - weekCheck: Function to look up a project template week by ID
    static func importProjectWeekRoleAssignments(
        _ dtos: [ProjectWeekRoleAssignmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectWeekRoleAssignment>,
        weekCheck: EntityExistsCheck<ProjectTemplateWeek>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing project week role assignment: \(error)")
                continue
            }

            let assignment = ProjectWeekRoleAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                weekID: dto.weekID,
                studentID: dto.studentID,
                roleID: dto.roleID,
                week: nil
            )

            do {
                if let week = try weekCheck(dto.weekID) {
                    assignment.week = week
                }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check week for project week role assignment: \(error)")
            }

            modelContext.insert(assignment)
        }
    }

    // MARK: - Project Sessions

    /// Imports project sessions from DTOs.
    static func importProjectSessions(_ dtos: [ProjectSessionDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<ProjectSession>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            ProjectSession(id: dto.id, createdAt: dto.createdAt, projectID: dto.projectID, meetingDate: dto.meetingDate, chapterOrPages: dto.chapterOrPages, notes: dto.notes, agendaItemsJSON: dto.agendaItemsJSON, templateWeekID: dto.templateWeekID)
        }
    }

    // MARK: - Work Check-Ins

    static func importWorkCheckIns(
        _ dtos: [WorkCheckInDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkCheckIn>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let workUUID = UUID(uuidString: dto.workID) else { continue }
            let checkIn = WorkCheckIn(
                id: dto.id,
                workID: workUUID,
                date: dto.date,
                status: WorkCheckInStatus(rawValue: dto.statusRaw) ?? .scheduled,
                purpose: dto.purpose,
                note: dto.note
            )
            // Link to work if exists
            do {
                if let work = try workCheck(workUUID) {
                    checkIn.work = work
                }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check work for check-in: \(error)")
            }
            modelContext.insert(checkIn)
        }
    }

    // MARK: - Work Steps

    static func importWorkSteps(
        _ dtos: [WorkStepDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkStep>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = WorkStep(
                id: dto.id,
                orderIndex: dto.orderIndex,
                title: dto.title,
                instructions: dto.instructions,
                completedAt: dto.completedAt,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        step.work = work
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check work for step: \(error)")
                }
            }
            modelContext.insert(step)
        }
    }

    // MARK: - Work Participants

    static func importWorkParticipants(
        _ dtos: [WorkParticipantEntityDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkParticipantEntity>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let participant = WorkParticipantEntity(id: dto.id, studentID: studentUUID, completedAt: dto.completedAt)
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        participant.work = work
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check work for participant: \(error)")
                }
            }
            modelContext.insert(participant)
        }
    }

    // MARK: - Practice Sessions

    static func importPracticeSessions(_ dtos: [PracticeSessionDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<PracticeSession>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let session = PracticeSession()
            session.id = dto.id
            session.createdAt = dto.createdAt
            session.date = dto.date
            session.duration = dto.duration
            session.studentIDs = dto.studentIDs
            session.workItemIDs = dto.workItemIDs
            session.sharedNotes = dto.sharedNotes
            session.location = dto.location
            session.practiceQuality = dto.practiceQuality
            session.independenceLevel = dto.independenceLevel
            session.askedForHelp = dto.askedForHelp
            session.helpedPeer = dto.helpedPeer
            session.struggledWithConcept = dto.struggledWithConcept
            session.madeBreakthrough = dto.madeBreakthrough
            session.needsReteaching = dto.needsReteaching
            session.readyForCheckIn = dto.readyForCheckIn
            session.readyForAssessment = dto.readyForAssessment
            session.checkInScheduledFor = dto.checkInScheduledFor
            session.followUpActions = dto.followUpActions
            session.materialsUsed = dto.materialsUsed
            return session
        }
    }

    // MARK: - Lesson Attachments

    static func importLessonAttachments(
        _ dtos: [LessonAttachmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonAttachment>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let attachment = LessonAttachment()
            attachment.id = dto.id
            attachment.fileName = dto.fileName
            attachment.fileRelativePath = dto.fileRelativePath
            attachment.attachedAt = dto.attachedAt
            attachment.fileType = dto.fileType
            attachment.fileSizeBytes = dto.fileSizeBytes
            attachment.scopeRaw = dto.scopeRaw
            attachment.notes = dto.notes
            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        attachment.lesson = lesson
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check lesson for attachment: \(error)")
                }
            }
            modelContext.insert(attachment)
        }
    }

    // MARK: - Lesson Presentations

    static func importLessonPresentations(_ dtos: [LessonPresentationDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<LessonPresentation>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let lp = LessonPresentation(
                id: dto.id,
                createdAt: dto.createdAt,
                studentID: dto.studentID,
                lessonID: dto.lessonID,
                presentationID: dto.presentationID,
                trackID: dto.trackID,
                trackStepID: dto.trackStepID,
                state: LessonPresentationState(rawValue: dto.stateRaw) ?? .presented,
                presentedAt: dto.presentedAt,
                lastObservedAt: dto.lastObservedAt,
                masteredAt: dto.masteredAt,
                notes: dto.notes
            )
            return lp
        }
    }

    // MARK: - Note Templates

    static func importNoteTemplates(_ dtos: [NoteTemplateDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<NoteTemplate>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            NoteTemplate(
                id: dto.id,
                createdAt: dto.createdAt,
                title: dto.title,
                body: dto.body,
                category: NoteCategory(rawValue: dto.categoryRaw) ?? .general,
                sortOrder: dto.sortOrder,
                isBuiltIn: dto.isBuiltIn
            )
        }
    }

    // MARK: - Meeting Templates

    static func importMeetingTemplates(_ dtos: [MeetingTemplateDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<MeetingTemplate>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            MeetingTemplate(
                id: dto.id,
                createdAt: dto.createdAt,
                name: dto.name,
                reflectionPrompt: dto.reflectionPrompt,
                focusPrompt: dto.focusPrompt,
                requestsPrompt: dto.requestsPrompt,
                guideNotesPrompt: dto.guideNotesPrompt,
                sortOrder: dto.sortOrder,
                isActive: dto.isActive,
                isBuiltIn: dto.isBuiltIn
            )
        }
    }

    // MARK: - Reminders

    static func importReminders(_ dtos: [ReminderDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Reminder>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            Reminder(
                id: dto.id,
                title: dto.title,
                notes: dto.notes,
                dueDate: dto.dueDate,
                isCompleted: dto.isCompleted,
                completedAt: dto.completedAt,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
        }
    }

    // MARK: - Calendar Events

    static func importCalendarEvents(_ dtos: [CalendarEventDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<CalendarEvent>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let e = CalendarEvent(
                id: dto.id,
                title: dto.title,
                startDate: dto.startDate,
                endDate: dto.endDate,
                location: dto.location,
                notes: dto.notes,
                isAllDay: dto.isAllDay
            )
            return e
        }
    }

    // MARK: - Tracks

    static func importTracks(_ dtos: [TrackDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Track>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let t = Track()
            t.id = dto.id
            t.title = dto.title
            t.createdAt = dto.createdAt
            return t
        }
    }

    // MARK: - Track Steps

    static func importTrackSteps(
        _ dtos: [TrackStepDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TrackStep>,
        trackCheck: EntityExistsCheck<Track>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = TrackStep()
            step.id = dto.id
            step.orderIndex = dto.orderIndex
            step.lessonTemplateID = dto.lessonTemplateID
            step.createdAt = dto.createdAt
            if let trackID = dto.trackID {
                do {
                    if let track = try trackCheck(trackID) {
                        step.track = track
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check track for step: \(error)")
                }
            }
            modelContext.insert(step)
        }
    }

    // MARK: - Student Track Enrollments

    static func importStudentTrackEnrollments(_ dtos: [StudentTrackEnrollmentDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<StudentTrackEnrollment>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let e = StudentTrackEnrollment()
            e.id = dto.id
            e.createdAt = dto.createdAt
            e.studentID = dto.studentID
            e.trackID = dto.trackID
            e.startedAt = dto.startedAt
            e.isActive = dto.isActive
            e.notes = dto.notes
            return e
        }
    }

    // MARK: - Group Tracks

    static func importGroupTracks(_ dtos: [GroupTrackDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<GroupTrack>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let g = GroupTrack(
                id: dto.id,
                subject: dto.subject,
                group: dto.group,
                isSequential: dto.isSequential,
                isExplicitlyDisabled: dto.isExplicitlyDisabled,
                createdAt: dto.createdAt
            )
            return g
        }
    }

    // MARK: - Documents

    static func importDocuments(
        _ dtos: [DocumentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Document>,
        studentCheck: EntityExistsCheck<Student>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let d = Document(
                id: dto.id,
                title: dto.title,
                category: dto.category,
                uploadDate: dto.uploadDate
            )
            if let studentID = dto.studentID {
                do {
                    if let student = try studentCheck(studentID) {
                        d.student = student
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check student for document: \(error)")
                }
            }
            modelContext.insert(d)
        }
    }

    // MARK: - Supplies

    static func importSupplies(_ dtos: [SupplyDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Supply>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let s = Supply(
                id: dto.id,
                name: dto.name,
                category: SupplyCategory(rawValue: dto.categoryRaw) ?? .other,
                location: dto.location,
                currentQuantity: dto.currentQuantity,
                minimumThreshold: dto.minimumThreshold,
                reorderAmount: dto.reorderAmount,
                unit: dto.unit,
                notes: dto.notes,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return s
        }
    }

    // MARK: - Supply Transactions

    static func importSupplyTransactions(
        _ dtos: [SupplyTransactionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<SupplyTransaction>,
        supplyCheck: EntityExistsCheck<Supply>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let t = SupplyTransaction(
                id: dto.id,
                supplyID: dto.supplyID,
                date: dto.date,
                quantityChange: dto.quantityChange,
                reason: dto.reason
            )
            if let supplyUUID = UUID(uuidString: dto.supplyID) {
                do {
                    if let supply = try supplyCheck(supplyUUID) {
                        t.supply = supply
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check supply for transaction: \(error)")
                }
            }
            modelContext.insert(t)
        }
    }

    // MARK: - Procedures

    static func importProcedures(_ dtos: [ProcedureDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Procedure>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let p = Procedure(
                id: dto.id,
                title: dto.title,
                summary: dto.summary,
                content: dto.content,
                category: ProcedureCategory(rawValue: dto.categoryRaw) ?? .other,
                icon: dto.icon,
                relatedProcedureIDs: dto.relatedProcedureIDs,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return p
        }
    }

    // MARK: - Schedules

    static func importSchedules(_ dtos: [ScheduleDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Schedule>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let s = Schedule(
                id: dto.id,
                name: dto.name,
                notes: dto.notes,
                colorHex: dto.colorHex,
                icon: dto.icon,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return s
        }
    }

    // MARK: - Schedule Slots

    static func importScheduleSlots(
        _ dtos: [ScheduleSlotDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ScheduleSlot>,
        scheduleCheck: EntityExistsCheck<Schedule>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let slot = ScheduleSlot(
                id: dto.id,
                scheduleID: dto.scheduleID,
                studentID: dto.studentID,
                weekday: Weekday(rawValue: dto.weekdayRaw) ?? .monday,
                timeString: dto.timeString,
                sortOrder: dto.sortOrder,
                notes: dto.notes,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            if let scheduleUUID = UUID(uuidString: dto.scheduleID) {
                do {
                    if let schedule = try scheduleCheck(scheduleUUID) {
                        slot.schedule = schedule
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check schedule for slot: \(error)")
                }
            }
            modelContext.insert(slot)
        }
    }

    // MARK: - Issues

    static func importIssues(_ dtos: [IssueDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Issue>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let i = Issue(
                title: dto.title,
                description: dto.issueDescription,
                category: IssueCategory(rawValue: dto.categoryRaw) ?? .other,
                priority: IssuePriority(rawValue: dto.priorityRaw) ?? .medium,
                status: IssueStatus(rawValue: dto.statusRaw) ?? .open,
                studentIDs: dto.studentIDs,
                location: dto.location
            )
            i.id = dto.id
            i.createdAt = dto.createdAt
            i.updatedAt = dto.updatedAt
            i.modifiedAt = dto.modifiedAt
            i.resolvedAt = dto.resolvedAt
            i.resolutionSummary = dto.resolutionSummary
            return i
        }
    }

    // MARK: - Issue Actions

    static func importIssueActions(
        _ dtos: [IssueActionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<IssueAction>,
        issueCheck: EntityExistsCheck<Issue>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let a = IssueAction(
                actionType: IssueActionType(rawValue: dto.actionTypeRaw) ?? .note,
                description: dto.actionDescription,
                actionDate: dto.actionDate,
                participantStudentIDs: dto.participantStudentIDs,
                nextSteps: dto.nextSteps,
                followUpRequired: dto.followUpRequired,
                followUpDate: dto.followUpDate
            )
            a.id = dto.id
            a.createdAt = dto.createdAt
            a.updatedAt = dto.updatedAt
            a.modifiedAt = dto.modifiedAt
            a.issueID = dto.issueID
            a.followUpCompleted = dto.followUpCompleted
            if let issueUUID = UUID(uuidString: dto.issueID) {
                do {
                    if let issue = try issueCheck(issueUUID) {
                        a.issue = issue
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check issue for action: \(error)")
                }
            }
            modelContext.insert(a)
        }
    }

    // MARK: - Development Snapshots

    static func importDevelopmentSnapshots(_ dtos: [DevelopmentSnapshotDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<DevelopmentSnapshot>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let s = DevelopmentSnapshot(
                id: dto.id,
                studentID: dto.studentID,
                generatedAt: dto.generatedAt,
                lookbackDays: dto.lookbackDays,
                analysisVersion: dto.analysisVersion,
                overallProgress: dto.overallProgress,
                keyStrengths: dto.keyStrengths,
                areasForGrowth: dto.areasForGrowth,
                developmentalMilestones: dto.developmentalMilestones,
                observedPatterns: dto.observedPatterns,
                behavioralTrends: dto.behavioralTrends,
                socialEmotionalInsights: dto.socialEmotionalInsights,
                recommendedNextLessons: dto.recommendedNextLessons,
                suggestedPracticeFocus: dto.suggestedPracticeFocus,
                interventionSuggestions: dto.interventionSuggestions,
                totalNotesAnalyzed: dto.totalNotesAnalyzed,
                practiceSessionsAnalyzed: dto.practiceSessionsAnalyzed,
                workCompletionsAnalyzed: dto.workCompletionsAnalyzed,
                averagePracticeQuality: dto.averagePracticeQuality,
                independenceLevel: dto.independenceLevel,
                rawAnalysisJSON: dto.rawAnalysisJSON
            )
            s.userNotes = dto.userNotes
            s.isReviewed = dto.isReviewed
            s.sharedWithParents = dto.sharedWithParents
            s.sharedAt = dto.sharedAt
            return s
        }
    }

    // MARK: - Todo Items

    static func importTodoItems(_ dtos: [TodoItemDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodoItem>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let t = TodoItem(id: dto.id, title: dto.title, notes: dto.notes, createdAt: dto.createdAt, orderIndex: dto.orderIndex)
            t.isCompleted = dto.isCompleted
            t.completedAt = dto.completedAt
            t.dueDate = dto.dueDate
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.recurrence = RecurrencePattern(rawValue: dto.recurrenceRaw) ?? .none
            t.studentIDs = dto.studentIDs
            t.linkedWorkItemID = dto.linkedWorkItemID
            t.attachmentPaths = dto.attachmentPaths
            t.estimatedMinutes = dto.estimatedMinutes
            t.actualMinutes = dto.actualMinutes
            t.reminderDate = dto.reminderDate
            t.reflectionNotes = dto.reflectionNotes
            t.tags = dto.tags
            t.locationName = dto.locationName
            t.locationLatitude = dto.locationLatitude
            t.locationLongitude = dto.locationLongitude
            t.locationRadius = dto.locationRadius
            t.notifyOnEntry = dto.notifyOnEntry
            t.notifyOnExit = dto.notifyOnExit
            return t
        }
    }

    // MARK: - Todo Subtasks

    static func importTodoSubtasks(
        _ dtos: [TodoSubtaskDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TodoSubtask>,
        todoCheck: EntityExistsCheck<TodoItem>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let s = TodoSubtask(id: dto.id, title: dto.title, orderIndex: dto.orderIndex, createdAt: dto.createdAt)
            s.isCompleted = dto.isCompleted
            s.completedAt = dto.completedAt
            if let todoID = dto.todoID {
                do {
                    if let todo = try todoCheck(todoID) {
                        s.todo = todo
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check todo for subtask: \(error)")
                }
            }
            modelContext.insert(s)
        }
    }

    // MARK: - Todo Templates

    static func importTodoTemplates(_ dtos: [TodoTemplateDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodoTemplate>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let t = TodoTemplate(id: dto.id, name: dto.name, title: dto.title, notes: dto.notes, createdAt: dto.createdAt)
            t.priority = TodoPriority(rawValue: dto.priorityRaw) ?? .none
            t.defaultEstimatedMinutes = dto.defaultEstimatedMinutes
            t.defaultStudentIDs = dto.defaultStudentIDs
            t.useCount = dto.useCount
            return t
        }
    }

    // MARK: - Today Agenda Orders

    static func importTodayAgendaOrders(_ dtos: [TodayAgendaOrderDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<TodayAgendaOrder>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let a = TodayAgendaOrder(
                day: dto.day,
                itemType: AgendaItemType(rawValue: dto.itemTypeRaw) ?? .lesson,
                itemID: dto.itemID,
                position: dto.position
            )
            a.id = dto.id
            return a
        }
    }
}
