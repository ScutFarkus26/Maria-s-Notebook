import Foundation
import SwiftData

// MARK: - Meeting Fetching

extension TodayDataFetcher {

    // MARK: - Scheduled Meetings Fetching

    /// Result of fetching scheduled meetings.
    struct ScheduledMeetingsFetchResult {
        let meetings: [ScheduledMeeting]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches scheduled meetings for a specific day.
    static func fetchScheduledMeetings(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> ScheduledMeetingsFetchResult {
        let descriptor = FetchDescriptor<ScheduledMeeting>(
            predicate: #Predicate { $0.date >= day && $0.date < nextDay },
            sortBy: [SortDescriptor(\ScheduledMeeting.createdAt)]
        )
        let meetings = context.safeFetch(descriptor)
        let studentIDs = Set(meetings.compactMap { $0.studentIDUUID })
        return ScheduledMeetingsFetchResult(meetings: meetings, neededStudentIDs: studentIDs)
    }

    // MARK: - Completed Meetings Fetching

    struct CompletedMeetingsFetchResult {
        let meetings: [StudentMeeting]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches completed meetings (StudentMeeting with completed == true) for a specific day.
    static func fetchCompletedMeetings(
        day: Date,
        nextDay: Date,
        context: ModelContext
    ) -> CompletedMeetingsFetchResult {
        let descriptor = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate { $0.completed == true && $0.date >= day && $0.date < nextDay },
            sortBy: [SortDescriptor(\StudentMeeting.date)]
        )
        let meetings = context.safeFetch(descriptor)
        let studentIDs = Set(meetings.compactMap { $0.studentIDUUID })
        return CompletedMeetingsFetchResult(meetings: meetings, neededStudentIDs: studentIDs)
    }
}
