import Foundation
import CoreData

@Observable
@MainActor
final class BookClubSessionsViewModel {
    func grouped(_ sessions: [CDBookClubSession]) -> [(status: BookClubSessionStatus, sessions: [CDBookClubSession])] {
        let buckets = Dictionary(grouping: sessions, by: \.status)
        return BookClubSessionStatus.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { status in
                guard let group = buckets[status], !group.isEmpty else { return nil }
                let ordered = group.sorted { lhs, rhs in
                    let lhsDate = lhs.startDate ?? lhs.createdAt ?? .distantPast
                    let rhsDate = rhs.startDate ?? rhs.createdAt ?? .distantPast
                    return lhsDate > rhsDate
                }
                return (status, ordered)
            }
    }

    /// Returns the packet for a session, or nil if the linked packet has been deleted.
    func packet(for session: CDBookClubSession, in context: NSManagedObjectContext) -> CDBookClubPacket? {
        guard let packetUUID = session.packetUUID else { return nil }
        return context.object(CDBookClubPacket.self, id: packetUUID)
    }

    /// Returns the next non-completed meeting for a session, or nil if all are done.
    func nextMeeting(for session: CDBookClubSession) -> CDBookClubMeeting? {
        session.orderedMeetings.first { !$0.isCompleted }
    }

    /// Returns the resolved student records in roster order.
    func roster(for session: CDBookClubSession, in context: NSManagedObjectContext) -> [CDStudent] {
        let ids = session.studentIDs
        guard !ids.isEmpty else { return [] }
        let request: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
        request.predicate = NSPredicate(format: "id IN %@", ids as CVarArg)
        let students = context.safeFetch(request)
        let ordered: [CDStudent] = ids.compactMap { id in
            students.first { $0.id == id }
        }
        return ordered
    }
}
