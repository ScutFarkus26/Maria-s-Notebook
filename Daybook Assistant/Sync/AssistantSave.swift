import Foundation
import CoreData

/// How the Assistant saves a mark (or a front-desk email send): save, then put
/// the records that save created into the classroom share explicitly rather
/// than wherever Core Data would file them
/// (`CDAttendanceStore.attachNewRecordsToClassroomShare`). The grid saves
/// through here. (Siri saves through `SiriAttendance`.)
@MainActor
enum AssistantSave {

    /// Returns whether the save worked. A failure is this phone's own store
    /// refusing the change, not the network: iCloud sending retries by itself.
    ///
    /// Every classroom record the save inserts goes to the share, not only
    /// the caller's `created`: one another screen left in the context (its
    /// own save failed) is saved here too, and was never filed.
    static func save(
        _ context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        created: [NSManagedObject]
    ) -> Bool {
        let inserted = recordsToFile(created: created, in: context)
        guard context.safeSave() else { return false }
        // Read after the save, which is what turns temporary IDs permanent.
        let ids = inserted.map(\.objectID)
        if let container, !ids.isEmpty {
            AssistantShareAttacher.shared.attach(ids, container: container, context: context)
        }
        return true
    }

    /// `created`, then every other classroom-share type the context is about
    /// to insert, each once.
    static func recordsToFile(created: [NSManagedObject], in context: NSManagedObjectContext) -> [NSManagedObject] {
        let others = context.insertedObjects.filter {
            CoreDataStack.sharedEntityNames.contains($0.entity.name ?? "")
        }
        var seen = Set<ObjectIdentifier>()
        return (created + others).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
