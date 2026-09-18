import Foundation
import CoreData

// MARK: - Meeting Fetching

extension TodayDataFetcher {

    // MARK: - Scheduled Meetings Fetching

    /// Result of fetching scheduled meetings.
    struct ScheduledMeetingsFetchResult {
        let meetings: [CDScheduledMeeting]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches scheduled meetings for a specific day.
    static func fetchScheduledMeetings(
        day: Date,
        nextDay: Date,
        context: NSManagedObjectContext
    ) -> ScheduledMeetingsFetchResult {
        let request = CDFetchRequest(CDScheduledMeeting.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            day as NSDate, nextDay as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDScheduledMeeting.createdAt, ascending: true)]
        let meetings = context.safeFetch(request)
        let studentIDs = Set(meetings.flatMap { meeting in
            meeting.allStudentIDs.compactMap { UUID(uuidString: $0) }
        })
        return ScheduledMeetingsFetchResult(meetings: meetings, neededStudentIDs: studentIDs)
    }

    // MARK: - Completed Meetings Fetching

    struct CompletedMeetingsFetchResult {
        let meetings: [CDStudentMeeting]
        let neededStudentIDs: Set<UUID>
    }

    /// Fetches completed meetings (CDStudentMeeting with completed == true) for a specific day.
    static func fetchCompletedMeetings(
        day: Date,
        nextDay: Date,
        context: NSManagedObjectContext
    ) -> CompletedMeetingsFetchResult {
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = NSPredicate(
            format: "completed == YES AND date >= %@ AND date < %@",
            day as NSDate, nextDay as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: true)]
        let meetings = context.safeFetch(request)
        let studentIDs = Set(meetings.compactMap(\.studentIDUUID))
        return CompletedMeetingsFetchResult(meetings: meetings, neededStudentIDs: studentIDs)
    }
}
