import Foundation
import SwiftData

// MARK: - Stream Fetching & Entity Counts

extension StreamingBackupWriter {

    func collectEntityCounts(modelContext: ModelContext) async throws -> [String: Int] {
        var counts: [String: Int] = [:]

        // Core entities
        counts["Student"] = try modelContext.fetchCount(FetchDescriptor<Student>())
        counts["Lesson"] = try modelContext.fetchCount(FetchDescriptor<Lesson>())
        // LegacyPresentation removed — fully migrated to LessonAssignment
        counts["LessonAssignment"] = try modelContext.fetchCount(FetchDescriptor<LessonAssignment>())
        counts["Note"] = try modelContext.fetchCount(FetchDescriptor<Note>())
        counts["NonSchoolDay"] = try modelContext.fetchCount(FetchDescriptor<NonSchoolDay>())
        counts["SchoolDayOverride"] = try modelContext.fetchCount(FetchDescriptor<SchoolDayOverride>())
        counts["StudentMeeting"] = try modelContext.fetchCount(FetchDescriptor<StudentMeeting>())
        counts["CommunityTopic"] = try modelContext.fetchCount(FetchDescriptor<CommunityTopic>())
        counts["ProposedSolution"] = try modelContext.fetchCount(FetchDescriptor<ProposedSolution>())
        counts["CommunityAttachment"] = try modelContext.fetchCount(FetchDescriptor<CommunityAttachment>())
        counts["AttendanceRecord"] = try modelContext.fetchCount(FetchDescriptor<AttendanceRecord>())
        counts["WorkCompletionRecord"] = try modelContext.fetchCount(FetchDescriptor<WorkCompletionRecord>())
        counts["Project"] = try modelContext.fetchCount(FetchDescriptor<Project>())
        counts["ProjectAssignmentTemplate"] = try modelContext.fetchCount(FetchDescriptor<ProjectAssignmentTemplate>())
        counts["ProjectSession"] = try modelContext.fetchCount(FetchDescriptor<ProjectSession>())
        counts["ProjectRole"] = try modelContext.fetchCount(FetchDescriptor<ProjectRole>())
        counts["ProjectTemplateWeek"] = try modelContext.fetchCount(FetchDescriptor<ProjectTemplateWeek>())
        counts["ProjectWeekRoleAssignment"] = try modelContext.fetchCount(FetchDescriptor<ProjectWeekRoleAssignment>())
        // Format v8+ entities
        counts["WorkCheckIn"] = try modelContext.fetchCount(FetchDescriptor<WorkCheckIn>())
        counts["WorkStep"] = try modelContext.fetchCount(FetchDescriptor<WorkStep>())
        counts["WorkParticipantEntity"] = try modelContext.fetchCount(FetchDescriptor<WorkParticipantEntity>())
        counts["PracticeSession"] = try modelContext.fetchCount(FetchDescriptor<PracticeSession>())
        counts["LessonAttachment"] = try modelContext.fetchCount(FetchDescriptor<LessonAttachment>())
        counts["LessonPresentation"] = try modelContext.fetchCount(FetchDescriptor<LessonPresentation>())
        counts["SampleWork"] = try modelContext.fetchCount(FetchDescriptor<SampleWork>())
        counts["SampleWorkStep"] = try modelContext.fetchCount(FetchDescriptor<SampleWorkStep>())
        counts["NoteTemplate"] = try modelContext.fetchCount(FetchDescriptor<NoteTemplate>())
        counts["MeetingTemplate"] = try modelContext.fetchCount(FetchDescriptor<MeetingTemplate>())
        counts["Reminder"] = try modelContext.fetchCount(FetchDescriptor<Reminder>())
        counts["CalendarEvent"] = try modelContext.fetchCount(FetchDescriptor<CalendarEvent>())
        counts["Track"] = try modelContext.fetchCount(FetchDescriptor<Track>())
        counts["TrackStep"] = try modelContext.fetchCount(FetchDescriptor<TrackStep>())
        counts["StudentTrackEnrollment"] = try modelContext.fetchCount(FetchDescriptor<StudentTrackEnrollment>())
        counts["GroupTrack"] = try modelContext.fetchCount(FetchDescriptor<GroupTrack>())
        counts["Document"] = try modelContext.fetchCount(FetchDescriptor<Document>())
        counts["Supply"] = try modelContext.fetchCount(FetchDescriptor<Supply>())
        counts["SupplyTransaction"] = try modelContext.fetchCount(FetchDescriptor<SupplyTransaction>())
        counts["Procedure"] = try modelContext.fetchCount(FetchDescriptor<Procedure>())
        counts["Schedule"] = try modelContext.fetchCount(FetchDescriptor<Schedule>())
        counts["ScheduleSlot"] = try modelContext.fetchCount(FetchDescriptor<ScheduleSlot>())
        counts["Issue"] = try modelContext.fetchCount(FetchDescriptor<Issue>())
        counts["IssueAction"] = try modelContext.fetchCount(FetchDescriptor<IssueAction>())
        counts["DevelopmentSnapshot"] = try modelContext.fetchCount(FetchDescriptor<DevelopmentSnapshot>())
        counts["TodoItem"] = try modelContext.fetchCount(FetchDescriptor<TodoItem>())
        counts["TodoSubtask"] = try modelContext.fetchCount(FetchDescriptor<TodoSubtask>())
        counts["TodoTemplate"] = try modelContext.fetchCount(FetchDescriptor<TodoTemplate>())
        counts["TodayAgendaOrder"] = try modelContext.fetchCount(FetchDescriptor<TodayAgendaOrder>())

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
