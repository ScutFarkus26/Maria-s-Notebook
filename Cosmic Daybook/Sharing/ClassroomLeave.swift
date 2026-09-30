import Foundation
import CloudKit
import CoreData

// What Leave Classroom purges, and how it fails. Its own file because the
// Daybook Assistant compiles ClassroomSharingService.swift by path without
// the notebook's other sharing extensions.

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
}

enum ClassroomLeaveError: LocalizedError {
    case unclearShare(Int)
    case shareNotReadable
    case notSaved

    var errorDescription: String? {
        switch self {
        case .unclearShare(let count):
            return "This device holds \(count) classroom shares and none is marked as the one it joined, " +
                "so nothing was removed."
        case .shareNotReadable:
            return "The class's share hasn't reached this device from iCloud yet, so nothing was removed. " +
                "Try Leave again in a minute."
        case .notSaved:
            return "The class came off this device, but leaving couldn't be saved. Try Leave again."
        }
    }
}
