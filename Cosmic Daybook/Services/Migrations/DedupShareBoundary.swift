import CloudKit
import CoreData
import Foundation
import os

/// Keeps deduplication away from a record that is moving out of the classroom share.
///
/// Core Data can't take a record out of a share, so `ClassroomShareRelease` inserts an
/// identical copy (same `id`) in the private default zone, waits until iCloud has it, then
/// deletes the shared original. On the guide's other devices both copies exist for a while.
/// If the id-based dedup there kept the shared one and deleted the private copy, that delete
/// would sync — and the release's own delete of the original would then leave no copy at
/// all. So a group of duplicates that has copies both inside and outside a share zone is left
/// alone: the release finishes it.
///
/// A copy not yet exported has no zone and counts as outside. Only the share's types can
/// straddle, so nothing else is looked up.
nonisolated enum DedupShareBoundary {
    private static let logger = Logger(subsystem: "CosmicDaybook", category: "Dedup")

    /// Test seam: where a record lives, instead of asking the container.
    @TaskLocal static var zoneNameOverride: (@Sendable (NSManagedObjectID) -> String?)?

    static func zoneName(of objectID: NSManagedObjectID, container: NSPersistentCloudKitContainer?) -> String? {
        if let zoneNameOverride { return zoneNameOverride(objectID) }
        return container?.recordID(for: objectID)?.zoneID.zoneName
    }

    /// True when `objects` (duplicates of one record) sit on both sides of the share boundary.
    static func spansShare(_ objects: [NSManagedObject], container: NSPersistentCloudKitContainer?) -> Bool {
        guard objects.count > 1, let entity = objects.first?.entity.name,
              CoreDataStack.sharedEntityNames.contains(entity) else { return false }
        guard container != nil || zoneNameOverride != nil else { return false }
        let sides = Set(objects.map {
            ClassroomShareScope.isShareZone(zoneName(of: $0.objectID, container: container))
        })
        guard sides.count > 1 else { return false }
        logger.notice(
            "Kept \(objects.count) copies of one \(entity, privacy: .public): in and out of the classroom share"
        )
        return true
    }
}
