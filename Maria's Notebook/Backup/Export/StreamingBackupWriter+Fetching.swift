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
        counts["CDStudent"] = try context.count(for:CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>)
        counts["CDLesson"] = try context.count(for:CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>)
        counts["CDLessonAssignment"] = try context.count(for:CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>)
        counts["CDNote"] = try context.count(for:CDNote.fetchRequest() as! NSFetchRequest<CDNote>)
        counts["CDNonSchoolDay"] = try context.count(for:CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>)
        counts["CDSchoolDayOverride"] = try context.count(for:CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>)
        counts["CDStudentMeeting"] = try context.count(for:CDStudentMeeting.fetchRequest() as! NSFetchRequest<CDStudentMeeting>)
        counts["CDCommunityTopicEntity"] = try context.count(for:CDCommunityTopicEntity.fetchRequest() as! NSFetchRequest<CDCommunityTopicEntity>)
        counts["ProposedSolution"] = try context.count(for:ProposedSolution.fetchRequest() as! NSFetchRequest<ProposedSolution>)
        counts["CommunityAttachment"] = try context.count(for:CommunityAttachment.fetchRequest() as! NSFetchRequest<CommunityAttachment>)
        counts["CDAttendanceRecord"] = try context.count(for:CDAttendanceRecord.fetchRequest() as! NSFetchRequest<CDAttendanceRecord>)
        counts["CDWorkCompletionRecord"] = try context.count(for:CDWorkCompletionRecord.fetchRequest() as! NSFetchRequest<CDWorkCompletionRecord>)
        counts["CDProject"] = try context.count(for:CDProject.fetchRequest() as! NSFetchRequest<CDProject>)
        counts["ProjectAssignmentTemplate"] = try context.count(for:ProjectAssignmentTemplate.fetchRequest() as! NSFetchRequest<ProjectAssignmentTemplate>)
        counts["CDProjectSession"] = try context.count(for:CDProjectSession.fetchRequest() as! NSFetchRequest<CDProjectSession>)
        counts["ProjectRole"] = try context.count(for:ProjectRole.fetchRequest() as! NSFetchRequest<ProjectRole>)
        counts["ProjectTemplateWeek"] = try context.count(for:ProjectTemplateWeek.fetchRequest() as! NSFetchRequest<ProjectTemplateWeek>)
        counts["ProjectWeekRoleAssignment"] = try context.count(for:ProjectWeekRoleAssignment.fetchRequest() as! NSFetchRequest<ProjectWeekRoleAssignment>)
        return counts
    }

    private func countV8Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["CDWorkModel"] = try context.count(for:CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>)
        counts["CDWorkCheckIn"] = try context.count(for:CDWorkCheckIn.fetchRequest() as! NSFetchRequest<CDWorkCheckIn>)
        counts["CDWorkStep"] = try context.count(for:CDWorkStep.fetchRequest() as! NSFetchRequest<CDWorkStep>)
        counts["WorkParticipantEntity"] = try context.count(for:WorkParticipantEntity.fetchRequest() as! NSFetchRequest<WorkParticipantEntity>)
        counts["CDPracticeSession"] = try context.count(for:CDPracticeSession.fetchRequest() as! NSFetchRequest<CDPracticeSession>)
        counts["LessonAttachment"] = try context.count(for:LessonAttachment.fetchRequest() as! NSFetchRequest<LessonAttachment>)
        counts["CDLessonPresentation"] = try context.count(for:CDLessonPresentation.fetchRequest() as! NSFetchRequest<CDLessonPresentation>)
        counts["CDSampleWork"] = try context.count(for:CDSampleWork.fetchRequest() as! NSFetchRequest<CDSampleWork>)
        counts["CDSampleWorkStep"] = try context.count(for:CDSampleWorkStep.fetchRequest() as! NSFetchRequest<CDSampleWorkStep>)
        counts["CDNoteTemplate"] = try context.count(for:CDNoteTemplate.fetchRequest() as! NSFetchRequest<CDNoteTemplate>)
        counts["CDMeetingTemplate"] = try context.count(for:CDMeetingTemplate.fetchRequest() as! NSFetchRequest<CDMeetingTemplate>)
        counts["CDReminder"] = try context.count(for:CDReminder.fetchRequest() as! NSFetchRequest<CDReminder>)
        counts["CDCalendarEvent"] = try context.count(for:CDCalendarEvent.fetchRequest() as! NSFetchRequest<CDCalendarEvent>)
        counts["CDTrackEntity"] = try context.count(for:CDTrackEntity.fetchRequest() as! NSFetchRequest<CDTrackEntity>)
        counts["TrackStep"] = try context.count(for:TrackStep.fetchRequest() as! NSFetchRequest<TrackStep>)
        counts["CDStudentTrackEnrollmentEntity"] = try context.count(for:CDStudentTrackEnrollmentEntity.fetchRequest() as! NSFetchRequest<CDStudentTrackEnrollmentEntity>)
        counts["CDGroupTrack"] = try context.count(for:CDGroupTrack.fetchRequest() as! NSFetchRequest<CDGroupTrack>)
        counts["CDDocument"] = try context.count(for:CDDocument.fetchRequest() as! NSFetchRequest<CDDocument>)
        counts["CDSupply"] = try context.count(for:CDSupply.fetchRequest() as! NSFetchRequest<CDSupply>)
        counts["SupplyTransaction"] = try context.count(for:SupplyTransaction.fetchRequest() as! NSFetchRequest<SupplyTransaction>)
        counts["CDProcedure"] = try context.count(for:CDProcedure.fetchRequest() as! NSFetchRequest<CDProcedure>)
        counts["CDSchedule"] = try context.count(for:CDSchedule.fetchRequest() as! NSFetchRequest<CDSchedule>)
        counts["CDScheduleSlot"] = try context.count(for:CDScheduleSlot.fetchRequest() as! NSFetchRequest<CDScheduleSlot>)
        counts["CDIssue"] = try context.count(for:CDIssue.fetchRequest() as! NSFetchRequest<CDIssue>)
        counts["IssueAction"] = try context.count(for:IssueAction.fetchRequest() as! NSFetchRequest<IssueAction>)
        counts["DevelopmentSnapshot"] = try context.count(for:DevelopmentSnapshot.fetchRequest() as! NSFetchRequest<DevelopmentSnapshot>)
        counts["CDTodoItem"] = try context.count(for:CDTodoItem.fetchRequest() as! NSFetchRequest<CDTodoItem>)
        counts["CDTodoSubtask"] = try context.count(for:CDTodoSubtask.fetchRequest() as! NSFetchRequest<CDTodoSubtask>)
        counts["CDTodoTemplate"] = try context.count(for:CDTodoTemplate.fetchRequest() as! NSFetchRequest<CDTodoTemplate>)
        counts["CDTodayAgendaOrder"] = try context.count(for:CDTodayAgendaOrder.fetchRequest() as! NSFetchRequest<CDTodayAgendaOrder>)
        return counts
    }

    private func countV11Entities(_ context: NSManagedObjectContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["PlanningRecommendation"] = try context.count(for:PlanningRecommendation.fetchRequest() as! NSFetchRequest<PlanningRecommendation>)
        counts["CDResource"] = try context.count(for:CDResource.fetchRequest() as! NSFetchRequest<CDResource>)
        counts["CDNoteStudentLink"] = try context.count(for:CDNoteStudentLink.fetchRequest() as! NSFetchRequest<CDNoteStudentLink>)
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
