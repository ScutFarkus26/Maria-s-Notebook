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

    /// How one try at putting new records into the classroom share went.
    nonisolated struct ShareAttachResult: Sendable {
        /// The records to try again later.
        var left: [NSManagedObjectID]
        /// CloudKit mirroring died this session (`ClassroomShareAttach`
        /// `mirroringDelegateDied`): every later `share(_:to:)` on this
        /// container fails the same way, by an exception no `catch` traps,
        /// so nothing may try again until the stack is rebuilt or relaunched.
        var mirroringStopped = false
    }

    private static let shareLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "AttendanceShare"
    )

    /// Puts `ids` — attendance records (or day locks) this device just saved
    /// into the shared store — into the classroom share. Records already in a
    /// share are left alone. Returns the ones to try again later (those that
    /// failed, and all of them when there is no share to put them in yet or
    /// it couldn't be read), and whether mirroring stopped.
    ///
    /// A container with no stores open is a stack closed for a rebuild
    /// (`AssistantStack.rebuild`), not a sign there's nothing to do: its
    /// records wait for the new stack. Reading that as "done" dropped them.
    /// (A stack open on one store, as in tests, has no share to put
    /// anything in.)
    @discardableResult
    static func attachNewRecordsToClassroomShare(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        pinContext: NSManagedObjectContext
    ) async -> ShareAttachResult {
        let stores = container.persistentStoreCoordinator.persistentStores
        guard !stores.isEmpty else {
            shareLogger.notice("No store open; \(ids.count, privacy: .public) record(s) wait for the next try")
            return ShareAttachResult(left: ids.filter { !$0.isTemporaryID })
        }
        let sharedStore = stores.first { $0.configurationName == CoreDataStack.sharedConfiguration }
        let permanent = ids.filter { !$0.isTemporaryID && $0.persistentStore === sharedStore }
        guard let sharedStore, let sharedStoreID = sharedStore.identifier, !permanent.isEmpty else {
            return ShareAttachResult(left: [])
        }

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
            return ShareAttachResult(left: permanent)
        }
        guard let share else {
            shareLogger.error("No classroom share to put \(permanent.count, privacy: .public) new record(s) into")
            return ShareAttachResult(left: permanent)
        }
        do {
            let waiting = try await ClassroomShareAttach.unshared(permanent, container: container)
            guard !waiting.isEmpty else {
                shareLogger.info("New record(s) already in the classroom share")
                return ShareAttachResult(left: [])
            }
            let outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
            let summary = "attached \(outcome.attached), failed \(outcome.failed.count)" +
                (outcome.stoppedBecause.map { ", stopped: \($0)" } ?? "")
            shareLogger.notice("Assistant records to classroom share: \(summary, privacy: .public)")
            return ShareAttachResult(left: outcome.failed, mirroringStopped: outcome.mirroringDelegateDied)
        } catch {
            shareLogger.error("Couldn't check the new records' share: \(error.localizedDescription, privacy: .public)")
            return ShareAttachResult(left: permanent)
        }
    }

    /// The share zone each of `ids` is in, read off the caller's actor: a
    /// record in no share has no entry. Throws when CloudKit can't say.
    @concurrent
    nonisolated static func shareZoneNames(
        of ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer
    ) async throws -> [NSManagedObjectID: String] {
        guard !ids.isEmpty else { return [:] }
        return try container.fetchShares(matching: ids).mapValues(\.recordID.zoneID.zoneName)
    }

    /// Deletes those of `ids` that still exist and are in no share, on a
    /// fresh background context (a view context can still hold objects a
    /// purge removed), and returns how many. For the Assistant's marks that
    /// never went into the share when she leaves: the purge takes only the
    /// class's zone. A record in a share is never deleted here: its delete
    /// would reach the guide. Throws, deleting nothing, when CloudKit can't
    /// say which are shared.
    @concurrent
    nonisolated static func deleteUnsharedRecords(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer
    ) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let context = container.newBackgroundContext()
        let existing = context.performAndWait { ids.filter { (try? context.existingObject(with: $0)) != nil } }
        guard !existing.isEmpty else { return 0 }
        let inShare = try container.fetchShares(matching: existing)
        let outside = existing.filter { inShare[$0] == nil }
        guard !outside.isEmpty else { return 0 }
        return try context.performAndWait {
            for id in outside { context.delete(try context.existingObject(with: id)) }
            try context.save()
            return outside.count
        }
    }
}
