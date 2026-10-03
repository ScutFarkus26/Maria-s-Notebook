import CloudKit
import CoreData
import Foundation

// What the classroom share holds, against what it should hold this school year
// (`ClassroomShareScope`). Read-only: Settings shows the differences; only Set Up
// Classroom Sharing ("Add Them to the Share") and `ClassroomShareRelease` act on them.

extension ClassroomSharingService {

    /// Per type, what the pinned share holds and what this school year's share should
    /// hold. Nil when there is nothing to read or CloudKit can't say.
    static func shareContents(coreDataStack: CoreDataStack) async -> ClassroomShareContents? {
        guard coreDataStack.isCloudKitActive, let store = coreDataStack.privatePersistentStore else { return nil }
        let pinnedZone = CDClassroomMembership.pinnedZoneName(in: coreDataStack.viewContext)
        let container = coreDataStack.container
        let scope = ClassroomShareScope()
        let storeID = store.identifier
        let (everything, inScope) = await classroomRecordIDsWithScope(
            storeID: storeID, container: container, scope: scope
        )
        return await countInShare(everything, inScope: inScope, zone: pinnedZone, container: container)
    }

    /// Every record of the share's types, and the ones `scope` keeps, in one read.
    @concurrent
    private static func classroomRecordIDsWithScope(
        storeID: String?,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async -> (everything: [String: [NSManagedObjectID]], inScope: [String: [NSManagedObjectID]]) {
        let context = container.newBackgroundContext()
        return await context.perform {
            (
                recordIDs(storeID: storeID, context: context, scope: nil),
                recordIDs(storeID: storeID, context: context, scope: scope)
            )
        }
    }

    @concurrent
    private static func countInShare(
        _ everything: [String: [NSManagedObjectID]],
        inScope: [String: [NSManagedObjectID]],
        zone: String?,
        container: NSPersistentCloudKitContainer
    ) async -> ClassroomShareContents? {
        var contents = ClassroomShareContents()
        var sharedIDs = Set<NSManagedObjectID>()
        for (entity, ids) in everything {
            let scoped = inScope[entity] ?? []
            contents.inScope[entity] = scoped.count
            guard let zone, !ids.isEmpty else {
                contents.inShare[entity] = 0
                contents.inScopeAndShared[entity] = 0
                continue
            }
            guard let shares = try? container.fetchShares(matching: ids) else { return nil }
            let shared = Set(shares.filter { $0.value.recordID.zoneID.zoneName == zone }.keys)
            sharedIDs.formUnion(shared)
            contents.inShare[entity] = shared.count
            contents.inScopeAndShared[entity] = scoped.filter { shared.contains($0) }.count
        }
        contents.mixedDuplicates = await mixedDuplicateCount(everything, sharedIDs: sharedIDs, container: container)
        return contents
    }

    /// Records of the share's student types that exist twice, once in the share and once
    /// outside it: a release caught partway (`ClassroomShareRelease` finishes them).
    @concurrent
    private static func mixedDuplicateCount(
        _ everything: [String: [NSManagedObjectID]],
        sharedIDs: Set<NSManagedObjectID>,
        container: NSPersistentCloudKitContainer
    ) async -> Int {
        let context = container.newBackgroundContext()
        return await context.perform {
            var count = 0
            for entity in ["Student", "AttendanceRecord"] {
                let ids = everything[entity] ?? []
                guard ids.count > 1 else { continue }
                var byRecordID: [UUID: [NSManagedObjectID]] = [:]
                for id in ids {
                    guard let object = try? context.existingObject(with: id),
                          let uuid = object.value(forKey: "id") as? UUID else { continue }
                    byRecordID[uuid, default: []].append(id)
                }
                for group in byRecordID.values where group.count > 1 {
                    let sides = Set(group.map { sharedIDs.contains($0) })
                    if sides.count > 1 { count += 1 }
                }
            }
            return count
        }
    }

    /// Object IDs of the classroom share's types in `store`, by entity, read on a background
    /// context without faulting any row: every record, or with `scope` only the ones this
    /// school year's share should hold.
    @concurrent
    static func classroomRecordIDs(
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope?
    ) async -> [String: [NSManagedObjectID]] {
        let storeID = store.identifier
        let context = container.newBackgroundContext()
        return await context.perform {
            recordIDs(storeID: storeID, context: context, scope: scope)
        }
    }

    /// On `context`'s queue. The store goes by identifier: the object itself isn't Sendable.
    nonisolated private static func recordIDs(
        storeID: String?,
        context: NSManagedObjectContext,
        scope: ClassroomShareScope?
    ) -> [String: [NSManagedObjectID]] {
        guard let store = context.persistentStoreCoordinator?.persistentStores.first(where: {
            $0.identifier == storeID
        }) else { return [:] }
        let belonging = scope?.belongingStudentIDs(in: context, store: store) ?? []
        var result: [String: [NSManagedObjectID]] = [:]
        for entity in ClassroomShareSetupReport.orderedEntityNames {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
            request.affectedStores = [store]
            request.resultType = .managedObjectIDResultType
            request.predicate = scope?.predicate(for: entity, belongingStudentIDs: belonging)
            result[entity] = (try? context.fetch(request)) ?? []
        }
        return result
    }
}

/// What the classroom share holds, against what this school year's share should hold.
nonisolated struct ClassroomShareContents: Sendable, Equatable {
    /// Per type, records in the pinned share, whatever their school year.
    var inShare: [String: Int] = [:]
    /// Per type, records this school year's share should hold (`ClassroomShareScope`).
    var inScope: [String: Int] = [:]
    /// Per type, records that should be shared and are.
    var inScopeAndShared: [String: Int] = [:]
    /// Records held twice, in the share and outside it: a release caught partway.
    var mixedDuplicates = 0

    /// Records that belong in the share and aren't in it.
    var outside: Int {
        inScope.reduce(0) { $0 + max(0, $1.value - (inScopeAndShared[$1.key] ?? 0)) }
    }

    /// Records in the share that no longer belong there (earlier school years).
    var toRelease: Int {
        ClassroomShareSetupReport.orderedEntityNames.reduce(0) { $0 + toRelease(of: $1) }
    }

    func toRelease(of entity: String) -> Int {
        max(0, (inShare[entity] ?? 0) - (inScopeAndShared[entity] ?? 0))
    }

    /// "40 students, 3,908 attendance marks, 16 days off, 2 locked days".
    var summary: String {
        ClassroomShareSetupReport.orderedEntityNames.compactMap { entity in
            let count = inShare[entity] ?? 0
            guard count > 0 || entity == "Student" else { return nil }
            return ClassroomShareSetupReport.describe(count, entity)
        }
        .joined(separator: ", ")
    }
}
