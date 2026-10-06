import Foundation
@preconcurrency import CoreData

// MARK: - Which records the guard takes, and how it reads them back

extension SharedStoreOrphanGuard {

    /// The classroom-share types among `inserted` that landed in the lead
    /// guide's private store. An assistant's records go to the shared store
    /// and are attached by the companion itself.
    static func classroomInserts(
        _ inserted: Set<NSManagedObject>,
        privateStore: NSPersistentStore?
    ) -> [NSManagedObjectID] {
        classroomIDs(inserted.map(\.objectID), privateStore: privateStore)
    }

    /// The classroom-share types among `ids` that are permanent and in the
    /// lead guide's private store.
    static func classroomIDs(_ ids: [NSManagedObjectID], privateStore: NSPersistentStore?) -> [NSManagedObjectID] {
        guard let privateStore else { return [] }
        return ids.filter {
            CoreDataStack.sharedEntityNames.contains($0.entity.name ?? "")
                && $0.persistentStore === privateStore && !$0.isTemporaryID
        }
    }

    /// Students a save *updated* in the private store. A student who re-enrols
    /// after leaving in an earlier year is outside the share, and nothing else
    /// would bring her back. Only she is queued: the pass that finds her
    /// unshared brings this year's attendance with her (`thisYearsAttendance`),
    /// so an ordinary edit to a shared student costs one entry and one check.
    /// Until 2026-10-05 each edit queued every mark of hers from this year too,
    /// which filled the list past its cap with records already shared (#3).
    static func returningStudentRecords(
        _ updated: Set<NSManagedObject>,
        in stack: CoreDataStack
    ) -> [NSManagedObjectID] {
        guard let privateStore = stack.privatePersistentStore else { return [] }
        return updated.compactMap { $0 as? CDStudent }
            .map(\.objectID)
            .filter { $0.persistentStore === privateStore && !$0.isTemporaryID }
    }

    /// The waiting records, sorted: those that still exist and belong in the
    /// share this school year, and the URIs of those that exist but fall
    /// outside it. Deleted ones are in neither.
    struct Sorted: Sendable {
        var belonging: [NSManagedObjectID] = []
        var outsideScope: [String] = []
    }

    @concurrent
    static func sort(
        _ uris: [String],
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async -> Sorted {
        let coordinator = container.persistentStoreCoordinator
        let context = container.newBackgroundContext()
        return await context.perform {
            var existing: [NSManagedObjectID] = []
            var uriByID: [NSManagedObjectID: String] = [:]
            for uri in uris {
                guard let url = URL(string: uri),
                      let id = coordinator.managedObjectID(forURIRepresentation: url),
                      (try? context.existingObject(with: id)) != nil else { continue }
                existing.append(id)
                uriByID[id] = uri
            }
            let belonging = scope.filter(existing, in: context)
            let kept = Set(belonging)
            let outside = existing.filter { !kept.contains($0) }.compactMap { uriByID[$0] }
            return Sorted(belonging: belonging, outsideScope: outside)
        }
    }

    /// The object IDs among `uris` whose records still exist and belong in the share.
    @concurrent
    static func existingIDs(
        for uris: [String],
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async -> [NSManagedObjectID] {
        await sort(uris, container: container, scope: scope).belonging
    }

    /// This school year's attendance, in the store with `storeID`, of
    /// `students`: what goes into the share with a returning student found
    /// unshared.
    @concurrent
    static func thisYearsAttendance(
        ofStudents students: [NSManagedObjectID],
        storeID: String,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async -> [NSManagedObjectID] {
        guard !students.isEmpty else { return [] }
        let context = container.newBackgroundContext()
        return await context.perform {
            guard let store = context.persistentStoreCoordinator?.persistentStores
                .first(where: { $0.identifier == storeID }) else { return [] }
            let keys = Set(students.compactMap { id in
                (try? context.existingObject(with: id) as? CDStudent)?.id
                    .map { ClassroomShareScope.normalizedID($0.uuidString) }
            })
            guard !keys.isEmpty else { return [] }
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "AttendanceRecord")
            request.resultType = .managedObjectIDResultType
            request.affectedStores = [store]
            request.predicate = scope.predicate(for: "AttendanceRecord", belongingStudentIDs: keys)
            return (try? context.fetch(request)) ?? []
        }
    }
}
