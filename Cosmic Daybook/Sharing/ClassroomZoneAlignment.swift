import Foundation
import CoreData
import CloudKit
import OSLog

/// Keeps the records the assistant's companion app reads in the classroom's
/// share zone.
///
/// A share covers one zone, and an assistant sees only what is in it. The lead
/// guide's store once minted several shares, and zone repair filed records into
/// whichever one came first, so 24 of the 29 days off sat outside the
/// classroom's zone where an assistant could never see them. This moves the
/// companion's entities — students, attendance and the school calendar — into
/// the classroom share's zone. Everything else stays where it is: the companion
/// never reads it.
///
/// Lead guide only, after zone repair at the end of post-launch work. With a
/// single share every shared record is already in the classroom's zone, so the
/// pass only looks when the store holds more than one; it keeps running each
/// launch because an older build on another device still files new records by
/// the old first-share rule until it updates.
enum ClassroomZoneAlignment {
    private static let logger = Logger.classroomSharing

    /// What the companion app reads (see `AssistantAttendanceViewModel`).
    nonisolated static let entityNames = ["Student", "AttendanceRecord", "NonSchoolDay", "SchoolDayOverride"]

    static func runIfNeeded(coreDataStack: CoreDataStack, policy: EnergyPolicy = .shared) async {
        guard coreDataStack.isCloudKitActive,
              !policy.shouldDeferMaintenance,
              !SharedStoreZoneRepair.isCircuitBreakerOpen,
              let store = coreDataStack.privatePersistentStore else { return }
        let container = coreDataStack.container
        let context = coreDataStack.viewContext
        guard CDClassroomMembership.currentRole(in: context) == .leadGuide,
              let shares = try? container.fetchShares(in: store), shares.count > 1,
              let classroom = CDClassroomMembership.classroomShare(among: shares, in: context)
        else { return }

        let zoneName = classroom.recordID.zoneID.zoneName
        let misplaced = await misplacedIDs(outside: zoneName, in: store, container: container)
        guard !misplaced.isEmpty else { return }

        logger.notice(
            "Moving \(misplaced.count, privacy: .public) record(s) into classroom zone \(zoneName, privacy: .public)"
        )
        var moved = 0
        for start in stride(from: 0, to: misplaced.count, by: 200) {
            let chunk = Array(misplaced[start..<min(start + 200, misplaced.count)])
            do {
                try await SharedStoreZoneRepair.shareOffMain(chunkIDs: chunk, share: classroom, container: container)
                moved += chunk.count
            } catch {
                let ns = error as NSError
                logger.error("""
                    Classroom zone move stopped after \(moved, privacy: .public) of \
                    \(misplaced.count, privacy: .public): \(ns.domain, privacy: .public) \(ns.code, privacy: .public)
                    """)
                return
            }
        }
        logger.notice("Moved \(moved, privacy: .public) record(s) into the classroom zone")
    }

    /// The companion's records that sit in some share other than the
    /// classroom's. Records in no share are zone repair's to attach.
    private nonisolated static func misplacedIDs(
        outside zoneName: String,
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID] {
        let context = container.newBackgroundContext()
        return await context.perform {
            var ids: [NSManagedObjectID] = []
            for name in entityNames {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: name)
                request.resultType = .managedObjectIDResultType
                request.affectedStores = [store]
                ids += (try? context.fetch(request)) ?? []
            }
            guard !ids.isEmpty, let inShare = try? container.fetchShares(matching: ids) else { return [] }
            return ids.filter { id in
                guard let share = inShare[id] else { return false }
                return share.recordID.zoneID.zoneName != zoneName
            }
        }
    }
}
