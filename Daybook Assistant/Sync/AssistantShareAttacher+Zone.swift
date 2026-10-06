import Foundation
import CoreData
import OSLog

// The class's own zone. With two share zones in her shared store, a new mark
// could land in the one that isn't her class's and still count as filed. The
// attacher keeps such a mark waiting, so the sync line and Leave count it as
// unsent, and logs it. It is never moved: `share(_:to:)` on a record already
// in a share is what stopped sync for the session on 2026-09-27.

extension AssistantShareAttacher {
    private static let zoneLogger = Logger.app(category: "shareAttach")

    /// Of `ids`, just put into a share, those not in the pinned class's
    /// zone, logged. None when there's no pin to compare with (the only
    /// share in her store was used), or CloudKit can't say: the attach
    /// itself went through.
    static func outsidePinnedZone(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext
    ) async -> [NSManagedObjectID] {
        guard !ids.isEmpty, let pinned = CDClassroomMembership.pinnedZoneName(in: context) else { return [] }
        let zones: [NSManagedObjectID: String]
        do {
            zones = try await CDAttendanceStore.shareZoneNames(of: ids, container: container)
        } catch {
            zoneLogger.error(
                "Couldn't check which share new marks went into: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        let strays = strays(among: ids, zones: zones, pinned: pinned)
        if !strays.isEmpty {
            zoneLogger.error(
                "\(strays.count, privacy: .public) mark(s) aren't in the class's share zone; they wait, unmoved"
            )
        }
        return strays
    }

    /// The records whose share zone isn't `pinned`, or that are in no share.
    nonisolated static func strays(
        among ids: [NSManagedObjectID], zones: [NSManagedObjectID: String], pinned: String
    ) -> [NSManagedObjectID] {
        ids.filter { zones[$0] != pinned }
    }
}
