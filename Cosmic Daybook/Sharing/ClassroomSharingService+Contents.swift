import CloudKit
import CoreData
import Foundation

// What the classroom share holds, against what it should hold this school year
// (`ClassroomShareScope`). Read-only: Settings shows the differences; only Set Up
// Classroom Sharing ("Add Them to the Share") and `ClassroomShareRelease` act on them.

extension ClassroomSharingService {

    /// Per type, what the pinned share holds and what this school year's share should
    /// hold. Nil when there is nothing to read or CloudKit can't say. `entities` narrows
    /// the read to some of the share's types (Restock's banner reads only its own three);
    /// the others are left out of the result.
    static func shareContents(
        coreDataStack: CoreDataStack,
        entities: [String] = ClassroomShareSetupReport.orderedEntityNames
    ) async -> ClassroomShareContents? {
        guard coreDataStack.isCloudKitActive, let store = coreDataStack.privatePersistentStore else { return nil }
        let pinnedZone = CDClassroomMembership.pinnedZoneName(in: coreDataStack.viewContext)
        let container = coreDataStack.container
        let scope = ClassroomShareScope()
        let storeID = store.identifier
        let (everything, inScope) = await classroomRecordIDsWithScope(
            storeID: storeID, container: container, scope: scope, entities: entities
        )
        return await countInShare(everything, inScope: inScope, zone: pinnedZone, container: container) { ids in
            try container.fetchShares(matching: ids).mapValues { $0.recordID.zoneID.zoneName }
        }
    }

    /// Every record of the share's types, and the ones `scope` keeps, in one read.
    @concurrent
    private static func classroomRecordIDsWithScope(
        storeID: String?,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope,
        entities: [String]
    ) async -> (everything: [String: [NSManagedObjectID]], inScope: [String: [NSManagedObjectID]]) {
        let context = container.newBackgroundContext()
        return await context.perform {
            (
                recordIDs(storeID: storeID, context: context, scope: nil, entities: entities),
                recordIDs(storeID: storeID, context: context, scope: scope, entities: entities)
            )
        }
    }

    /// Counts what `zone`'s share holds. `shareZones` answers, for each record
    /// in a share, its share's zone (`fetchShares(matching:)`; a test stands
    /// in for it).
    @concurrent
    static func countInShare(
        _ everything: [String: [NSManagedObjectID]],
        inScope: [String: [NSManagedObjectID]],
        zone: String?,
        container: NSPersistentCloudKitContainer,
        shareZones: @Sendable ([NSManagedObjectID]) throws -> [NSManagedObjectID: String]
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
            guard let zones = try? shareZones(ids) else { return nil }
            let shared = Set(zones.filter { $0.value == zone }.keys)
            sharedIDs.formUnion(shared)
            contents.inShare[entity] = shared.count
            contents.inScopeAndShared[entity] = scoped.filter { shared.contains($0) }.count
            contents.inScopeInOtherShare[entity] = scoped.filter { zones[$0] != nil && !shared.contains($0) }.count
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
        scope: ClassroomShareScope?,
        entities: [String] = ClassroomShareSetupReport.orderedEntityNames
    ) -> [String: [NSManagedObjectID]] {
        guard let store = context.persistentStoreCoordinator?.persistentStores.first(where: {
            $0.identifier == storeID
        }) else { return [:] }
        // Only the student types' scope goes by who belongs this year.
        let needsStudents = entities.contains("Student") || entities.contains("AttendanceRecord")
        let belonging = needsStudents ? (scope?.belongingStudentIDs(in: context, store: store) ?? []) : []
        var result: [String: [NSManagedObjectID]] = [:]
        for entity in ClassroomShareSetupReport.orderedEntityNames where entities.contains(entity) {
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
    /// Per type, records that should be shared and are in another share
    /// instead: a share zone left from before (the 2026-09 incident).
    /// `share(_:to:)` can't move a record out of a share, so "Add them to the
    /// share" never adds these (bug hunt 2026-11-02, #32).
    var inScopeInOtherShare: [String: Int] = [:]
    /// Records held twice, in the share and outside it: a release caught partway.
    var mixedDuplicates = 0

    /// Restock's share types: staples, needs and the staples' history.
    static let restockEntityNames = ["Supply", "OrderItem", "SupplyTransaction"]

    /// Records that belong in the share and aren't in it.
    var outside: Int {
        inScope.keys.reduce(0) { $0 + outside(of: $1) }
    }

    /// Records of one type that belong in the share and aren't in it.
    func outside(of entity: String) -> Int {
        max(0, (inScope[entity] ?? 0) - (inScopeAndShared[entity] ?? 0))
    }

    /// Records that belong in the share and are in another share instead
    /// (`inScopeInOtherShare`).
    var inOtherShare: Int {
        inScope.keys.reduce(0) { $0 + inOtherShare(of: $1) }
    }

    func inOtherShare(of entity: String) -> Int {
        min(inScopeInOtherShare[entity] ?? 0, outside(of: entity))
    }

    /// Records that belong in the share and are in no share: what "Add them to
    /// the share" can add.
    var addable: Int { outside - inOtherShare }

    /// "2 of them are in an old classroom share from before, so they can't be
    /// added from here." Nil when none are.
    var inOtherShareLine: String? {
        let count = inOtherShare
        guard count > 0 else { return nil }
        return count == 1
            ? "1 of them is in an old classroom share from before, so it can't be added from here."
            : "\(count.formatted()) of them are in an old classroom share from before, "
                + "so they can't be added from here."
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
