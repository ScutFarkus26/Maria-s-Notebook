import Foundation
import SwiftData

/// Handles importing entities from backup DTOs into the database.
///
/// This extracts the entity import logic from BackupService for better
/// testability and separation of concerns.
enum BackupEntityImporter {

    /// Type alias for a function that checks if an entity with a given ID exists
    typealias EntityExistsCheck<T: PersistentModel> = (UUID) throws -> T?

    // MARK: - Students

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    ///
    /// - Parameters:
    ///   - dtos: The student DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a student already exists
    /// - Returns: Dictionary mapping student IDs to imported Student objects
    static func importStudents(
        _ dtos: [StudentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Student>
    ) rethrows -> [UUID: Student] {
        var studentsByID: [UUID: Student] = [:]

        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let student = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: dto.level == .upper ? .upper : .lower
            )
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.map { $0.uuidString }
            student.manualOrder = dto.manualOrder
            modelContext.insert(student)
            studentsByID[student.id] = student
        }

        return studentsByID
    }

    // MARK: - Lessons

    /// Imports lessons from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The lesson DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a lesson already exists
    static func importLessons(
        _ dtos: [LessonDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let lesson = Lesson(
                id: dto.id,
                name: dto.name,
                subject: dto.subject,
                group: dto.group,
                orderInGroup: dto.orderInGroup,
                subheading: dto.subheading,
                writeUp: dto.writeUp
            )
            if let pages = dto.pagesFileRelativePath {
                lesson.pagesFileRelativePath = pages
            }
            modelContext.insert(lesson)
        }
    }

    // MARK: - Community Topics

    /// Imports community topics from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The community topic DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a topic already exists
    static func importCommunityTopics(
        _ dtos: [CommunityTopicDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CommunityTopic>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let topic = CommunityTopic(
                id: dto.id,
                title: dto.title,
                issueDescription: dto.issueDescription,
                createdAt: dto.createdAt,
                addressedDate: dto.addressedDate,
                resolution: dto.resolution
            )
            topic.raisedBy = dto.raisedBy
            topic.tags = dto.tags
            modelContext.insert(topic)
        }
    }

    // MARK: - Work Plan Items

    /// Imports work plan items from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The work plan item DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an item already exists
    static func importWorkPlanItems(
        _ dtos: [WorkPlanItemDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkPlanItem>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let item = WorkPlanItem(
                workID: dto.workID,
                scheduledDate: dto.scheduledDate,
                reason: nil,
                note: dto.note
            )
            item.id = dto.id
            item.reasonRaw = dto.reason.isEmpty ? nil : dto.reason
            item.note = dto.note
            modelContext.insert(item)
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
            guard (try? lessonCheck(dto.lessonID)) != nil else { continue }
            // Skip if already exists
            if (try? studentLessonCheck(dto.id)) != nil { continue }

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
                if let student = try? studentCheck(studentID) {
                    linkedStudents.append(student)
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
            if (try? existingCheck(dto.id)) != nil { continue }

            let note = Note(
                id: dto.id,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                body: dto.body,
                imagePath: dto.imagePath
            )
            note.isPinned = dto.isPinned

            if let data = dto.scope.data(using: .utf8),
               let scope = try? JSONDecoder().decode(NoteScope.self, from: data) {
                note.scope = scope
            }

            if let lessonID = dto.lessonID,
               let lesson = try? lessonCheck(lessonID) {
                note.lesson = lesson
            }

            modelContext.insert(note)
        }
    }

    // MARK: - Non-School Days

    /// Imports non-school days from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The non-school day DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a day already exists
    static func importNonSchoolDays(
        _ dtos: [NonSchoolDayDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<NonSchoolDay>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let day = NonSchoolDay(id: dto.id, date: dto.date)
            day.reason = dto.reason
            modelContext.insert(day)
        }
    }

    // MARK: - School Day Overrides

    /// Imports school day overrides from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The school day override DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if an override already exists
    static func importSchoolDayOverrides(
        _ dtos: [SchoolDayOverrideDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<SchoolDayOverride>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let override = SchoolDayOverride(id: dto.id, date: dto.date)
            override.note = dto.note
            modelContext.insert(override)
        }
    }

    // MARK: - Student Meetings

    /// Imports student meetings from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The student meeting DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a meeting already exists
    static func importStudentMeetings(
        _ dtos: [StudentMeetingDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<StudentMeeting>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }
            let meeting = StudentMeeting(id: dto.id, studentID: dto.studentID, date: dto.date)
            meeting.completed = dto.completed
            meeting.reflection = dto.reflection
            meeting.focus = dto.focus
            meeting.requests = dto.requests
            meeting.guideNotes = dto.guideNotes
            modelContext.insert(meeting)
        }
    }

    // MARK: - Presentations

    /// Imports presentations from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The presentation DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a presentation already exists
    ///   - allStudentLessons: All student lessons for legacy ID matching
    static func importPresentations(
        _ dtos: [PresentationDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Presentation>,
        allStudentLessons: [StudentLesson]
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let presentation = Presentation(
                id: dto.id,
                createdAt: dto.createdAt,
                presentedAt: dto.presentedAt,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs
            )
            presentation.legacyStudentLessonID = dto.legacyStudentLessonID
            presentation.lessonTitleSnapshot = dto.lessonTitleSnapshot
            presentation.lessonSubtitleSnapshot = dto.lessonSubtitleSnapshot

            // Match legacy student lesson if not already set
            if presentation.legacyStudentLessonID == nil {
                if let matchingSL = allStudentLessons.first(where: { sl in
                    sl.lessonID == dto.lessonID && Set(sl.studentIDs) == Set(dto.studentIDs)
                }) {
                    presentation.legacyStudentLessonID = matchingSL.id.uuidString
                }
            }

            modelContext.insert(presentation)
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
            if (try? existingCheck(dto.id)) != nil { continue }

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
            if let lesson = try? lessonCheck(lessonUUID) {
                assignment.lesson = lesson
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
            if (try? existingCheck(dto.id)) != nil { continue }

            let solution = ProposedSolution(
                id: dto.id,
                title: dto.title,
                details: dto.details,
                proposedBy: dto.proposedBy,
                createdAt: dto.createdAt,
                isAdopted: dto.isAdopted,
                topic: nil
            )

            if let topicID = dto.topicID,
               let topic = try? topicCheck(topicID) {
                solution.topic = topic
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
            if (try? existingCheck(dto.id)) != nil { continue }

            let attachment = CommunityAttachment(
                id: dto.id,
                filename: dto.filename,
                kind: CommunityAttachment.Kind(rawValue: dto.kind) ?? .file,
                data: nil,
                createdAt: dto.createdAt,
                topic: nil
            )

            if let topicID = dto.topicID,
               let topic = try? topicCheck(topicID) {
                attachment.topic = topic
            }

            modelContext.insert(attachment)
        }
    }

    // MARK: - Attendance Records

    /// Imports attendance records from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The attendance record DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a record already exists
    static func importAttendanceRecords(
        _ dtos: [AttendanceRecordDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<AttendanceRecord>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let absenceReason = dto.absenceReason.flatMap { AbsenceReason(rawValue: $0) } ?? .none
            let record = AttendanceRecord(
                id: dto.id,
                studentID: dto.studentID,
                date: dto.date,
                status: AttendanceStatus(rawValue: dto.status) ?? .unmarked,
                absenceReason: absenceReason,
                note: dto.note
            )
            modelContext.insert(record)
        }
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The work completion record DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a record already exists
    static func importWorkCompletionRecords(
        _ dtos: [WorkCompletionRecordDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkCompletionRecord>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let record = WorkCompletionRecord(
                id: dto.id,
                workID: dto.workID,
                studentID: dto.studentID,
                completedAt: dto.completedAt,
                note: dto.note
            )
            modelContext.insert(record)
        }
    }

    // MARK: - Projects

    /// Imports projects from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a project already exists
    static func importProjects(
        _ dtos: [ProjectDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Project>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let project = Project(
                id: dto.id,
                createdAt: dto.createdAt,
                title: dto.title,
                bookTitle: dto.bookTitle,
                memberStudentIDs: dto.memberStudentIDs
            )
            modelContext.insert(project)
        }
    }

    // MARK: - Project Roles

    /// Imports project roles from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project role DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a role already exists
    static func importProjectRoles(
        _ dtos: [ProjectRoleDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectRole>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let role = ProjectRole(
                id: dto.id,
                createdAt: dto.createdAt,
                projectID: dto.projectID,
                title: dto.title,
                summary: dto.summary,
                instructions: dto.instructions
            )
            modelContext.insert(role)
        }
    }

    // MARK: - Project Template Weeks

    /// Imports project template weeks from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project template week DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a week already exists
    static func importProjectTemplateWeeks(
        _ dtos: [ProjectTemplateWeekDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectTemplateWeek>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let week = ProjectTemplateWeek(
                id: dto.id,
                createdAt: dto.createdAt,
                projectID: dto.projectID,
                weekIndex: dto.weekIndex,
                readingRange: dto.readingRange,
                agendaItemsJSON: dto.agendaItemsJSON,
                linkedLessonIDsJSON: dto.linkedLessonIDsJSON,
                workInstructions: dto.workInstructions
            )
            modelContext.insert(week)
        }
    }

    // MARK: - Project Assignment Templates

    /// Imports project assignment templates from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project assignment template DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a template already exists
    static func importProjectAssignmentTemplates(
        _ dtos: [ProjectAssignmentTemplateDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectAssignmentTemplate>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let template = ProjectAssignmentTemplate(
                id: dto.id,
                createdAt: dto.createdAt,
                projectID: dto.projectID,
                title: dto.title,
                instructions: dto.instructions,
                isShared: dto.isShared,
                defaultLinkedLessonID: dto.defaultLinkedLessonID
            )
            modelContext.insert(template)
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
            if (try? existingCheck(dto.id)) != nil { continue }

            let assignment = ProjectWeekRoleAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                weekID: dto.weekID,
                studentID: dto.studentID,
                roleID: dto.roleID,
                week: nil
            )

            if let week = try? weekCheck(dto.weekID) {
                assignment.week = week
            }

            modelContext.insert(assignment)
        }
    }

    // MARK: - Project Sessions

    /// Imports project sessions from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The project session DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a session already exists
    static func importProjectSessions(
        _ dtos: [ProjectSessionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<ProjectSession>
    ) rethrows {
        for dto in dtos {
            if (try? existingCheck(dto.id)) != nil { continue }

            let session = ProjectSession(
                id: dto.id,
                createdAt: dto.createdAt,
                projectID: dto.projectID,
                meetingDate: dto.meetingDate,
                chapterOrPages: dto.chapterOrPages,
                notes: dto.notes,
                agendaItemsJSON: dto.agendaItemsJSON,
                templateWeekID: dto.templateWeekID
            )
            modelContext.insert(session)
        }
    }
}
