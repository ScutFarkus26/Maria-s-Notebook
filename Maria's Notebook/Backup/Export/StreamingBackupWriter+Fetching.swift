import Foundation
import CoreData

// MARK: - Stream Fetching & Entity Counts

extension StreamingBackupWriter {

    func collectEntityCounts(viewContext: NSManagedObjectContext) async throws -> [String: Int] {
        var counts = try countCoreEntities(viewContext)
        counts.merge(try countV8Entities(viewContext)) { _, new in new }
        counts.merge(try countV11Entities(viewContext)) { _, new in new }
        return counts
    }

    private func countCoreEntities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["Student"] = try context.count(for:NSFetchRequest<CDStudent>(entityName: "Student"))
        counts["Lesson"] = try context.count(for:NSFetchRequest<CDLesson>(entityName: "Lesson"))
        counts["LessonAssignment"] = try context.count(for:NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"))
        counts["Note"] = try context.count(for:NSFetchRequest<CDNote>(entityName: "Note"))
        counts["NonSchoolDay"] = try context.count(for:NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay"))
        counts["SchoolDayOverride"] = try context.count(for:NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride"))
        counts["StudentMeeting"] = try context.count(for:NSFetchRequest<CDStudentMeeting>(entityName: "StudentMeeting"))
        counts["CommunityTopic"] = try context.count(for:NSFetchRequest<CDCommunityTopicEntity>(entityName: "CommunityTopic"))
        counts["ProposedSolution"] = try context.count(for:NSFetchRequest<CDProposedSolutionEntity>(entityName: "ProposedSolution"))
        counts["CommunityAttachment"] = try context.count(for:NSFetchRequest<CDCommunityAttachmentEntity>(entityName: "CommunityAttachment"))
        counts["AttendanceRecord"] = try context.count(for:NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord"))
        counts["WorkCompletionRecord"] = try context.count(for:NSFetchRequest<CDWorkCompletionRecord>(entityName: "WorkCompletionRecord"))
        counts["Project"] = try context.count(for:NSFetchRequest<CDProject>(entityName: "Project"))
        counts["ProjectAssignmentTemplate"] = 0 // Deprecated
        counts["ProjectSession"] = try context.count(for:NSFetchRequest<CDProjectSession>(entityName: "ProjectSession"))
        counts["ProjectRole"] = try context.count(for:NSFetchRequest<CDProjectRole>(entityName: "ProjectRole"))
        counts["ProjectTemplateWeek"] = 0 // Deprecated
        counts["ProjectWeekRoleAssignment"] = 0 // Deprecated
        return counts
    }

    private func countV8Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["WorkModel"] = try context.count(for:NSFetchRequest<CDWorkModel>(entityName: "WorkModel"))
        counts["WorkCheckIn"] = try context.count(for:NSFetchRequest<CDWorkCheckIn>(entityName: "WorkCheckIn"))
        counts["WorkStep"] = try context.count(for:NSFetchRequest<CDWorkStep>(entityName: "WorkStep"))
        counts["WorkParticipantEntity"] = try context.count(for:NSFetchRequest<CDWorkParticipantEntity>(entityName: "WorkParticipantEntity"))
        counts["PracticeSession"] = try context.count(for:NSFetchRequest<CDPracticeSession>(entityName: "PracticeSession"))
        counts["LessonAttachment"] = try context.count(for:NSFetchRequest<CDLessonAttachment>(entityName: "LessonAttachment"))
        counts["LessonPresentation"] = try context.count(for:NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation"))
        counts["SampleWork"] = try context.count(for:NSFetchRequest<CDSampleWork>(entityName: "SampleWork"))
        counts["SampleWorkStep"] = try context.count(for:NSFetchRequest<CDSampleWorkStep>(entityName: "SampleWorkStep"))
        counts["NoteTemplate"] = try context.count(for:NSFetchRequest<CDNoteTemplate>(entityName: "NoteTemplate"))
        counts["MeetingTemplate"] = try context.count(for:NSFetchRequest<CDMeetingTemplate>(entityName: "MeetingTemplate"))
        counts["Reminder"] = try context.count(for:NSFetchRequest<CDReminder>(entityName: "Reminder"))
        counts["CalendarEvent"] = try context.count(for:NSFetchRequest<CDCalendarEvent>(entityName: "CalendarEvent"))
        counts["Track"] = try context.count(for:NSFetchRequest<CDTrackEntity>(entityName: "Track"))
        counts["TrackStep"] = try context.count(for:NSFetchRequest<CDTrackStepEntity>(entityName: "TrackStep"))
        counts["StudentTrackEnrollment"] = try context.count(for:NSFetchRequest<CDStudentTrackEnrollmentEntity>(entityName: "StudentTrackEnrollment"))
        counts["GroupTrack"] = try context.count(for:NSFetchRequest<CDGroupTrack>(entityName: "GroupTrack"))
        counts["Document"] = try context.count(for:NSFetchRequest<CDDocument>(entityName: "Document"))
        counts["Supply"] = try context.count(for:NSFetchRequest<CDSupply>(entityName: "Supply"))
        counts["Procedure"] = try context.count(for:NSFetchRequest<CDProcedure>(entityName: "Procedure"))
        counts["Schedule"] = try context.count(for:NSFetchRequest<CDSchedule>(entityName: "Schedule"))
        counts["ScheduleSlot"] = try context.count(for:NSFetchRequest<CDScheduleSlot>(entityName: "ScheduleSlot"))
        counts["Issue"] = try context.count(for:NSFetchRequest<CDIssue>(entityName: "Issue"))
        counts["IssueAction"] = try context.count(for:NSFetchRequest<CDIssueAction>(entityName: "IssueAction"))
        counts["DevelopmentSnapshot"] = try context.count(for:NSFetchRequest<CDDevelopmentSnapshotEntity>(entityName: "DevelopmentSnapshot"))
        counts["TodoItem"] = try context.count(for:NSFetchRequest<CDTodoItem>(entityName: "TodoItem"))
        counts["TodoSubtask"] = try context.count(for:NSFetchRequest<CDTodoSubtask>(entityName: "TodoSubtask"))
        counts["TodoTemplate"] = try context.count(for:NSFetchRequest<CDTodoTemplate>(entityName: "TodoTemplate"))
        counts["TodayAgendaOrder"] = try context.count(for:NSFetchRequest<CDTodayAgendaOrder>(entityName: "TodayAgendaOrder"))
        return counts
    }

    private func countV11Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["PlanningRecommendation"] = try context.count(for:NSFetchRequest<CDPlanningRecommendation>(entityName: "PlanningRecommendation"))
        counts["Resource"] = try context.count(for:NSFetchRequest<CDResource>(entityName: "Resource"))
        counts["NoteStudentLink"] = try context.count(for:NSFetchRequest<CDNoteStudentLink>(entityName: "NoteStudentLink"))
        return counts
    }

    func streamFetch<T: NSManagedObject>(
        _ type: T.Type,
        from context: NSManagedObjectContext,
        progress: @escaping (Int, String) -> Void
    ) async throws -> [Any] {
        var allDTOs: [Any] = []
        var offset = 0
        let typeName = String(describing: type)

        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            // SwiftData handles memory management internally
            let descriptor = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = configuration.batchSize

            // Only use autoreleasepool if needed for Objective-C bridging
            let batch: [T]
            if configuration.useAutoreleasePool {
                batch = try autoreleasepool {
                    try context.fetch(descriptor)
                }
            } else {
                batch = try context.fetch(descriptor)
            }

            guard !batch.isEmpty else { break }

            // Transform to DTOs - Swift ARC handles memory automatically
            let dtos = transformToDTOs(batch) as [Any]

            allDTOs.append(contentsOf: dtos)
            progress(batch.count, typeName)

            if batch.count < configuration.batchSize { break }
            offset += configuration.batchSize
        }

        return allDTOs
    }

    func streamFetchRaw<T: NSManagedObject>(
        _ type: T.Type,
        from context: NSManagedObjectContext
    ) async throws -> [T] {
        var allEntities: [T] = []
        var offset = 0

        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            let descriptor = NSFetchRequest<T>(entityName: T.entity().name ?? String(describing: T.self))
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = configuration.batchSize

            // Only use autoreleasepool if needed for Objective-C bridging
            let batch: [T]
            if configuration.useAutoreleasePool {
                batch = try autoreleasepool {
                    try context.fetch(descriptor)
                }
            } else {
                batch = try context.fetch(descriptor)
            }

            guard !batch.isEmpty else { break }

            allEntities.append(contentsOf: batch)

            if batch.count < configuration.batchSize { break }
            offset += configuration.batchSize
        }

        return allEntities
    }
}
