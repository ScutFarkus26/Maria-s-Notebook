import Foundation
import CoreData

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
        context: NSManagedObjectContext
    ) -> ScheduledMeetingsFetchResult {
        let request = CDFetchRequest(ScheduledMeeting.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            day as NSDate, nextDay as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduledMeeting.createdAt, ascending: true)]
        let meetings = context.safeFetch(request)
        let studentIDs = Set(meetings.compactMap(\.studentIDUUID))
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
        context: NSManagedObjectContext
    ) -> CompletedMeetingsFetchResult {
        let request = CDFetchRequest(StudentMeeting.self)
        request.predicate = NSPredicate(
            format: "completed == YES AND date >= %@ AND date < %@",
            day as NSDate, nextDay as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StudentMeeting.date, ascending: true)]
        let meetings = context.safeFetch(request)
        let studentIDs = Set(meetings.compactMap(\.studentIDUUID))
        return CompletedMeetingsFetchResult(meetings: meetings, neededStudentIDs: studentIDs)
    }
}
