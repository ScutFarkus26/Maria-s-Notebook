import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

// MARK: - An assistant's new records go into the classroom share
//
// On the lead guide's device a new mark lands in the private store and
// `SharedStoreOrphanGuard` attaches it to the classroom share. An assistant's
// mark lands in the shared store (`CDAttendanceStore.destinationStore`), and
// until 2026-09-28 which share zone it joined was left to Core Data. It is now
// put into the classroom share explicitly, right after the save that creates
// it: the pinned share, or — an assistant's shared store holding one share in
// the two-zone layout — the only share there is.
//
// Whether CloudKit accepts `share(_:to:)` from a participant for a record the
// participant created is one of the things Part 2 of the Production move tests;
// every outcome is logged, and a failure leaves the record where Core Data put it.

extension CDAttendanceStore {

    private static let shareLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "AttendanceShare"
    )

    /// Puts `ids` — attendance records (or day locks) this device just saved
    /// into the shared store — into the classroom share. Records already in a
    /// share are left alone.
    static func attachNewRecordsToClassroomShare(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        pinContext: NSManagedObjectContext
    ) async {
        let sharedStore = container.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        let permanent = ids.filter { !$0.isTemporaryID && $0.persistentStore === sharedStore }
        guard let sharedStore, let sharedStoreID = sharedStore.identifier, !permanent.isEmpty else { return }

        // Read off the main actor: this runs right after the save that created
        // the records, while CloudKit's export of that save may hold the store.
        let share: CKShare?
        do {
            share = try await ClassroomShareAttach.classroomShare(
                inStoreWithIdentifier: sharedStoreID,
                container: container,
                pinContext: pinContext,
                onlyShareFallback: true
            )
        } catch {
            shareLogger.error("Couldn't read the classroom share: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let share else {
            shareLogger.error("No classroom share to put \(permanent.count, privacy: .public) new record(s) into")
            return
        }
        do {
            let waiting = try await ClassroomShareAttach.unshared(permanent, container: container)
            guard !waiting.isEmpty else {
                shareLogger.info("New record(s) already in the classroom share")
                return
            }
            let outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
            let summary = "attached \(outcome.attached), failed \(outcome.failed.count)" +
                (outcome.stoppedBecause.map { ", stopped: \($0)" } ?? "")
            shareLogger.notice("Assistant records to classroom share: \(summary, privacy: .public)")
        } catch {
            shareLogger.error("Couldn't check the new records' share: \(error.localizedDescription, privacy: .public)")
        }
    }
}
