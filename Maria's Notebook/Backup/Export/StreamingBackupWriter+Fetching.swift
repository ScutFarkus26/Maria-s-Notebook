import Foundation
import SwiftData

// MARK: - Stream Fetching & Entity Counts

extension StreamingBackupWriter {

    func collectEntityCounts(modelContext: ModelContext) async throws -> [String: Int] {
        var counts = try countCoreEntities(modelContext)
        counts.merge(try countV8Entities(modelContext)) { _, new in new }
        counts.merge(try countV11Entities(modelContext)) { _, new in new }
        return counts
    }

    private func countCoreEntities(_ context: ModelContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["Student"] = try context.fetchCount(FetchDescriptor<Student>())
        counts["Lesson"] = try context.fetchCount(FetchDescriptor<Lesson>())
        counts["LessonAssignment"] = try context.fetchCount(FetchDescriptor<LessonAssignment>())
        counts["Note"] = try context.fetchCount(FetchDescriptor<Note>())
        counts["NonSchoolDay"] = try context.fetchCount(FetchDescriptor<NonSchoolDay>())
        counts["SchoolDayOverride"] = try context.fetchCount(FetchDescriptor<SchoolDayOverride>())
        counts["StudentMeeting"] = try context.fetchCount(FetchDescriptor<StudentMeeting>())
        counts["CommunityTopic"] = try context.fetchCount(FetchDescriptor<CommunityTopic>())
        counts["ProposedSolution"] = try context.fetchCount(FetchDescriptor<ProposedSolution>())
        counts["CommunityAttachment"] = try context.fetchCount(FetchDescriptor<CommunityAttachment>())
        counts["AttendanceRecord"] = try context.fetchCount(FetchDescriptor<AttendanceRecord>())
        counts["WorkCompletionRecord"] = try context.fetchCount(FetchDescriptor<WorkCompletionRecord>())
        counts["Project"] = try context.fetchCount(FetchDescriptor<Project>())
        counts["ProjectAssignmentTemplate"] = try context.fetchCount(FetchDescriptor<ProjectAssignmentTemplate>())
        counts["ProjectSession"] = try context.fetchCount(FetchDescriptor<ProjectSession>())
        counts["ProjectRole"] = try context.fetchCount(FetchDescriptor<ProjectRole>())
        counts["ProjectTemplateWeek"] = try context.fetchCount(FetchDescriptor<ProjectTemplateWeek>())
        counts["ProjectWeekRoleAssignment"] = try context.fetchCount(FetchDescriptor<ProjectWeekRoleAssignment>())
        return counts
    }

    private func countV8Entities(_ context: ModelContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["WorkModel"] = try context.fetchCount(FetchDescriptor<WorkModel>())
        counts["WorkCheckIn"] = try context.fetchCount(FetchDescriptor<WorkCheckIn>())
        counts["WorkStep"] = try context.fetchCount(FetchDescriptor<WorkStep>())
        counts["WorkParticipantEntity"] = try context.fetchCount(FetchDescriptor<WorkParticipantEntity>())
        counts["PracticeSession"] = try context.fetchCount(FetchDescriptor<PracticeSession>())
        counts["LessonAttachment"] = try context.fetchCount(FetchDescriptor<LessonAttachment>())
        counts["LessonPresentation"] = try context.fetchCount(FetchDescriptor<LessonPresentation>())
        counts["SampleWork"] = try context.fetchCount(FetchDescriptor<SampleWork>())
        counts["SampleWorkStep"] = try context.fetchCount(FetchDescriptor<SampleWorkStep>())
        counts["NoteTemplate"] = try context.fetchCount(FetchDescriptor<NoteTemplate>())
        counts["MeetingTemplate"] = try context.fetchCount(FetchDescriptor<MeetingTemplate>())
        counts["Reminder"] = try context.fetchCount(FetchDescriptor<Reminder>())
        counts["CalendarEvent"] = try context.fetchCount(FetchDescriptor<CalendarEvent>())
        counts["Track"] = try context.fetchCount(FetchDescriptor<Track>())
        counts["TrackStep"] = try context.fetchCount(FetchDescriptor<TrackStep>())
        counts["StudentTrackEnrollment"] = try context.fetchCount(FetchDescriptor<StudentTrackEnrollment>())
        counts["GroupTrack"] = try context.fetchCount(FetchDescriptor<GroupTrack>())
        counts["Document"] = try context.fetchCount(FetchDescriptor<Document>())
        counts["Supply"] = try context.fetchCount(FetchDescriptor<Supply>())
        counts["SupplyTransaction"] = try context.fetchCount(FetchDescriptor<SupplyTransaction>())
        counts["Procedure"] = try context.fetchCount(FetchDescriptor<Procedure>())
        counts["Schedule"] = try context.fetchCount(FetchDescriptor<Schedule>())
        counts["ScheduleSlot"] = try context.fetchCount(FetchDescriptor<ScheduleSlot>())
        counts["Issue"] = try context.fetchCount(FetchDescriptor<Issue>())
        counts["IssueAction"] = try context.fetchCount(FetchDescriptor<IssueAction>())
        counts["DevelopmentSnapshot"] = try context.fetchCount(FetchDescriptor<DevelopmentSnapshot>())
        counts["TodoItem"] = try context.fetchCount(FetchDescriptor<TodoItem>())
        counts["TodoSubtask"] = try context.fetchCount(FetchDescriptor<TodoSubtask>())
        counts["TodoTemplate"] = try context.fetchCount(FetchDescriptor<TodoTemplate>())
        counts["TodayAgendaOrder"] = try context.fetchCount(FetchDescriptor<TodayAgendaOrder>())
        return counts
    }

    private func countV11Entities(_ context: ModelContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["PlanningRecommendation"] = try context.fetchCount(FetchDescriptor<PlanningRecommendation>())
        counts["Resource"] = try context.fetchCount(FetchDescriptor<Resource>())
        counts["NoteStudentLink"] = try context.fetchCount(FetchDescriptor<NoteStudentLink>())
        return counts
    }

    func streamFetch<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext,
        progress: @escaping (Int, String) -> Void
    ) async throws -> [Any] {
        var allDTOs: [Any] = []
        var offset = 0
        let typeName = String(describing: type)

        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            // SwiftData handles memory management internally
            var descriptor = FetchDescriptor<T>()
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

    func streamFetchRaw<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) async throws -> [T] {
        var allEntities: [T] = []
        var offset = 0

        while true {
            // Modern approach: Use FetchDescriptor batch configuration
            var descriptor = FetchDescriptor<T>()
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
