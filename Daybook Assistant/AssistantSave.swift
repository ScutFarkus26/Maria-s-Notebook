import Foundation
import CoreData

/// How the Assistant saves a mark: save, then put the records that save
/// created into the classroom share explicitly rather than wherever Core
/// Data would file them (`CDAttendanceStore.attachNewRecordsToClassroomShare`).
/// The grid saves through here. (Siri saves through `SiriAttendance`.)
@MainActor
enum AssistantSave {

    /// Returns whether the save worked. A failure is this phone's own store
    /// refusing the change, not the network: iCloud sending retries by itself.
    static func save(
        _ context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        created: [CDAttendanceRecord]
    ) -> Bool {
        guard context.safeSave() else { return false }
        // Read after the save, which is what turns temporary IDs permanent.
        let ids = created.map(\.objectID)
        if let container, !ids.isEmpty {
            AssistantShareAttacher.shared.attach(ids, container: container, context: context)
        }
        return true
    }
}
