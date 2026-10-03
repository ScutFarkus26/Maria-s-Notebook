import Foundation
import CloudKit
import CoreData

// What Leave Classroom purges, and how it fails; and what to do after a
// failed join. Its own file because the Daybook Assistant compiles
// ClassroomSharingService.swift by path without the notebook's other sharing
// extensions, and both apps use these.

extension ClassroomSharingService {

    /// The share Leave purges: the pinned one, else the only share the
    /// store holds (a relaunch that hasn't read the share, or a row with no
    /// pin), else none when it holds none and no class either. Several with
    /// none pinned throws rather than guess (see
    /// `CDClassroomMembership.classroomShare`).
    ///
    /// A class on the device (`holdsClassroom`) whose share can't be read
    /// yet also throws. It happened on 2026-09-29, on a simulator whose
    /// CloudKit setup hadn't finished: Leave found no share, purged nothing
    /// and deleted the membership, so the phone said "Join a Classroom"
    /// while the account stayed a member of the class on iCloud.
    nonisolated static func shareToLeave(
        pinned: CKShare?, among shares: [CKShare], holdsClassroom: Bool = false
    ) throws -> CKShare? {
        if let pinned { return pinned }
        guard shares.count <= 1 else { throw ClassroomLeaveError.unclearShare(shares.count) }
        if shares.isEmpty, holdsClassroom { throw ClassroomLeaveError.shareNotReadable }
        return shares.first
    }

    /// Whether `store` holds any of a class: its children.
    static func holdsClassroom(_ store: NSPersistentStore, in context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDStudent.self)
        request.affectedStores = [store]
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    /// What to do after a failed join, to follow `AppErrorMessages.joinMessage`:
    /// a connection or account problem is fixed on this device, anything else
    /// by a fresh invitation.
    nonisolated static func joinAdvice(for error: Error) -> String {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, _), ("CKErrorDomain", 3), ("CKErrorDomain", 4):
            return "Check you're online, then open the invitation again."
        case ("CKErrorDomain", 9):
            return "Sign in to iCloud, then open the invitation again."
        case ("CKErrorDomain", 1), ("CKErrorDomain", 6), ("CKErrorDomain", 7):
            return "Wait a minute, then open the invitation again."
        default:
            return "Ask the lead guide for a new invitation."
        }
    }
}

enum ClassroomLeaveError: LocalizedError {
    case unclearShare(Int)
    case shareNotReadable
    case notSaved

    var errorDescription: String? {
        switch self {
        case .unclearShare(let count):
            return "This device has \(count) shared classes and can't tell which one it joined, " +
                "so nothing was removed."
        case .shareNotReadable:
            return "The class hasn't finished arriving from iCloud on this device, so nothing was removed. " +
                "Try Leave again in a minute."
        case .notSaved:
            return "The class came off this device, but leaving couldn't be saved. Try Leave again."
        }
    }
}
