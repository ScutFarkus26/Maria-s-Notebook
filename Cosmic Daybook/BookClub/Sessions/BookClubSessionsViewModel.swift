import Foundation
import CoreData

@Observable
final class BookClubSessionsViewModel {
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
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", ids as CVarArg)
        let students = context.safeFetch(request)
        let ordered: [CDStudent] = ids.compactMap { id in
            students.first { $0.id == id }
        }
        return ordered
    }
}
