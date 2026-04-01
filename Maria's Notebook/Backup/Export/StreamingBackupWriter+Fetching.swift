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
        counts["Student"] = try context.count(for:CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>)
        counts["Lesson"] = try context.count(for:CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>)
        counts["LessonAssignment"] = try context.count(for:CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>)
        counts["Note"] = try context.count(for:CDNote.fetchRequest() as! NSFetchRequest<CDNote>)
        counts["NonSchoolDay"] = try context.count(for:CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>)
        counts["SchoolDayOverride"] = try context.count(for:CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>)
        counts["StudentMeeting"] = try context.count(for:CDStudentMeeting.fetchRequest() as! NSFetchRequest<CDStudentMeeting>)
        counts["CommunityTopic"] = try context.count(for:CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>)
        counts["ProposedSolution"] = try context.count(for:CDProposedSolutionEntity.fetchRequest() as! NSFetchRequest<CDProposedSolutionEntity>)
        counts["CommunityAttachment"] = try context.count(for:CDCommunityAttachmentEntity.fetchRequest() as! NSFetchRequest<CDCommunityAttachmentEntity>)
        counts["AttendanceRecord"] = try context.count(for:CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>)
        counts["WorkCompletionRecord"] = try context.count(for:CDWorkCompletionRecord.fetchRequest() as! NSFetchRequest<CDWorkCompletionRecord>)
        counts["Project"] = try context.count(for:CDProject.fetchRequest() as! NSFetchRequest<CDProject>)
        counts["ProjectAssignmentTemplate"] = try context.count(for:CDProjectAssignmentTemplate.fetchRequest() as! NSFetchRequest<CDProjectAssignmentTemplate>)
        counts["ProjectSession"] = try context.count(for:CDProjectSession.fetchRequest() as! NSFetchRequest<CDProjectSession>)
        counts["ProjectRole"] = try context.count(for:CDProjectRole.fetchRequest() as! NSFetchRequest<CDProjectRole>)
        counts["ProjectTemplateWeek"] = try context.count(for:CDProjectTemplateWeek.fetchRequest() as! NSFetchRequest<CDProjectTemplateWeek>)
        counts["ProjectWeekRoleAssignment"] = try context.count(for:CDProjectWeekRoleAssignment.fetchRequest() as! NSFetchRequest<CDProjectWeekRoleAssignment>)
        return counts
    }

    private func countV8Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["WorkModel"] = try context.count(for:CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>)
        counts["WorkCheckIn"] = try context.count(for:CDWorkCheckIn.fetchRequest() as! NSFetchRequest<CDWorkCheckIn>)
        counts["WorkStep"] = try context.count(for:CDWorkStep.fetchRequest() as! NSFetchRequest<CDWorkStep>)
        counts["WorkParticipantEntity"] = try context.count(for:CDWorkParticipantEntity.fetchRequest() as! NSFetchRequest<CDWorkParticipantEntity>)
        counts["PracticeSession"] = try context.count(for:CDPracticeSession.fetchRequest() as! NSFetchRequest<CDPracticeSession>)
        counts["LessonAttachment"] = try context.count(for:CDLessonAttachment.fetchRequest() as! NSFetchRequest<CDLessonAttachment>)
        counts["LessonPresentation"] = try context.count(for:CDLessonPresentation.fetchRequest() as! NSFetchRequest<CDLessonPresentation>)
        counts["SampleWork"] = try context.count(for:CDSampleWork.fetchRequest() as! NSFetchRequest<CDSampleWork>)
        counts["SampleWorkStep"] = try context.count(for:CDSampleWorkStep.fetchRequest() as! NSFetchRequest<CDSampleWorkStep>)
        counts["NoteTemplate"] = try context.count(for:CDNoteTemplate.fetchRequest() as! NSFetchRequest<CDNoteTemplate>)
        counts["MeetingTemplate"] = try context.count(for:CDMeetingTemplate.fetchRequest() as! NSFetchRequest<CDMeetingTemplate>)
        counts["Reminder"] = try context.count(for:CDReminder.fetchRequest() as! NSFetchRequest<CDReminder>)
        counts["CalendarEvent"] = try context.count(for:CDCalendarEvent.fetchRequest() as! NSFetchRequest<CDCalendarEvent>)
        counts["Track"] = try context.count(for:CDTrackEntity.fetchRequest() as! NSFetchRequest<CDTrackEntity>)
        counts["TrackStep"] = try context.count(for:CDTrackStepEntity.fetchRequest() as! NSFetchRequest<CDTrackStepEntity>)
        counts["StudentTrackEnrollment"] = try context.count(for:CDStudentTrackEnrollmentEntity.fetchRequest() as! NSFetchRequest<CDStudentTrackEnrollmentEntity>)
        counts["GroupTrack"] = try context.count(for:CDGroupTrack.fetchRequest() as! NSFetchRequest<CDGroupTrack>)
        counts["Document"] = try context.count(for:CDDocument.fetchRequest() as! NSFetchRequest<CDDocument>)
        counts["Supply"] = try context.count(for:CDSupply.fetchRequest() as! NSFetchRequest<CDSupply>)
        counts["SupplyTransaction"] = try context.count(for:CDSupplyTransaction.fetchRequest() as! NSFetchRequest<CDSupplyTransaction>)
        counts["Procedure"] = try context.count(for:CDProcedure.fetchRequest() as! NSFetchRequest<CDProcedure>)
        counts["Schedule"] = try context.count(for:CDSchedule.fetchRequest() as! NSFetchRequest<CDSchedule>)
        counts["ScheduleSlot"] = try context.count(for:CDScheduleSlot.fetchRequest() as! NSFetchRequest<CDScheduleSlot>)
        counts["Issue"] = try context.count(for:CDIssue.fetchRequest() as! NSFetchRequest<CDIssue>)
        counts["IssueAction"] = try context.count(for:CDIssueAction.fetchRequest() as! NSFetchRequest<CDIssueAction>)
        counts["DevelopmentSnapshot"] = try context.count(for:CDDevelopmentSnapshotEntity.fetchRequest() as! NSFetchRequest<CDDevelopmentSnapshotEntity>)
        counts["TodoItem"] = try context.count(for:CDTodoItem.fetchRequest() as! NSFetchRequest<CDTodoItem>)
        counts["TodoSubtask"] = try context.count(for:CDTodoSubtask.fetchRequest() as! NSFetchRequest<CDTodoSubtask>)
        counts["TodoTemplate"] = try context.count(for:CDTodoTemplate.fetchRequest() as! NSFetchRequest<CDTodoTemplate>)
        counts["TodayAgendaOrder"] = try context.count(for:CDTodayAgendaOrder.fetchRequest() as! NSFetchRequest<CDTodayAgendaOrder>)
        return counts
    }

    private func countV11Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["PlanningRecommendation"] = try context.count(for:CDPlanningRecommendation.fetchRequest() as! NSFetchRequest<CDPlanningRecommendation>)
        counts["Resource"] = try context.count(for:CDResource.fetchRequest() as! NSFetchRequest<CDResource>)
        counts["NoteStudentLink"] = try context.count(for:CDNoteStudentLink.fetchRequest() as! NSFetchRequest<CDNoteStudentLink>)
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
            var descriptor = T.fetchRequest() as! NSFetchRequest<T>
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
            var descriptor = T.fetchRequest() as! NSFetchRequest<T>
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
