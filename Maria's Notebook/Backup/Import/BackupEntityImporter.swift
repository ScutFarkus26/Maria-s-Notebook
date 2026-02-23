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
}
