import CoreData
import Foundation

// Reading the store for the plan (`ClassroomShareRelease`): every Student and
// AttendanceRecord in the private store, with where each lives, whether it belongs, and
// whether a backup can hold it.

nonisolated extension ClassroomShareRelease {

    /// The planner's rows: every Student and AttendanceRecord in the private store, with
    /// where each lives and whether it belongs. Records in some other share are left out:
    /// nothing here ever touches another share.
    static func rows(
        container: NSPersistentCloudKitContainer,
        storeID: String,
        pinnedZone: String,
        scope: ClassroomShareScope,
        environment: Environment
    ) async throws -> [Row] {
        let context = container.newBackgroundContext()
        let read: (ids: [NSManagedObjectID], facts: [NSManagedObjectID: Facts])? = await context.perform {
            guard let store = store(storeID, in: context) else { return nil }
            let belonging = scope.belongingStudentIDs(in: context, store: store)
            var ids: [NSManagedObjectID] = []
            var facts: [NSManagedObjectID: Facts] = [:]
            for entity in ["Student", "AttendanceRecord"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                request.affectedStores = [store]
                for object in (try? context.fetch(request)) ?? [] {
                    ids.append(object.objectID)
                    facts[object.objectID] = Facts(object, belonging: belonging, scope: scope)
                }
            }
            return (ids, facts)
        }
        guard let read else { throw RunError.storeUnavailable }
        let zones = try await environment.shareZones(read.ids)
        return read.ids.compactMap { id in
            guard let facts = read.facts[id] else { return nil }
            let zone = zones[id]
            if let zone, zone != pinnedZone { return nil } // another share: never touched
            return Row(
                objectID: id, entity: facts.entity, recordID: facts.recordID,
                studentKey: facts.studentKey, isShared: zone != nil, belongs: facts.belongs,
                backupGap: facts.backupGap
            )
        }
    }

    /// What the planner needs of one object, read on its context's queue.
    struct Facts: Sendable {
        let entity: String
        let recordID: UUID?
        let studentKey: String
        let belongs: Bool
        let backupGap: BackupGap?

        init(_ object: NSManagedObject, belonging: Set<String>, scope: ClassroomShareScope) {
            entity = object.entity.name ?? ""
            recordID = object.value(forKey: "id") as? UUID
            if entity == "Student" {
                studentKey = ClassroomShareScope.normalizedID(recordID?.uuidString ?? "")
                belongs = belonging.contains(studentKey)
                backupGap = recordID == nil ? .noID : nil
            } else {
                let studentID = object.value(forKey: "studentID") as? String ?? ""
                let date = object.value(forKey: "date") as? Date
                studentKey = ClassroomShareScope.normalizedID(studentID)
                belongs = scope.attendanceBelongs(date: date, studentID: studentID, belongingStudentIDs: belonging)
                // The same tests as the backup's own (`BackupServiceHelpers.toDTOs`).
                if recordID == nil {
                    backupGap = .noID
                } else if date == nil {
                    backupGap = .noDate
                } else if UUID(uuidString: studentID) == nil {
                    backupGap = .noChild
                } else {
                    backupGap = nil
                }
            }
        }
    }
}
