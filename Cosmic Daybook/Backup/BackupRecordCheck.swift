import CoreData
import Foundation

/// Before a run deletes or changes records (Remove Last Year from the Share, Clean Up Old
/// Records), the backup made for it must hold every one of them, by `id`. Counting rows
/// isn't enough: a backup can hold as many rows of a type as the notebook while missing the
/// very record about to go.
nonisolated enum BackupRecordCheck {

    /// The records a run touches, by entity: their IDs, and how many have none.
    struct Needed: Sendable, Equatable {
        var ids: [String: Set<UUID>] = [:]
        var withoutID: [String: Int] = [:]

        var entityNames: Set<String> { Set(ids.keys).union(withoutID.keys) }
    }

    /// Checks the backup at `url` holds every one of `records`, read on `context` (a
    /// background context). Throws `BackupCheckError` with the reason otherwise.
    static func check(
        _ url: URL, holds records: [NSManagedObjectID], context: NSManagedObjectContext
    ) async throws {
        let needed = await context.perform { needs(of: records, in: context) }
        guard !needed.entityNames.isEmpty else { return }
        let held: [String: Set<UUID>]
        do {
            held = try await BackupImporter.recordIDs(at: url, of: needed.entityNames)
        } catch {
            throw ClassroomShareRelease.BackupCheckError(
                "The backup couldn't be read back (\(error.localizedDescription)). Nothing was changed."
            )
        }
        let rows = try await context.perform { try rowCounts(Array(needed.withoutID.keys), in: context) }
        if let problem = problem(needed: needed, held: held, notebookRows: rows) {
            throw ClassroomShareRelease.BackupCheckError(problem)
        }
    }

    /// What `records` are, read on `context`'s queue. One deleted since is left out: the run
    /// can't touch it either.
    static func needs(of records: [NSManagedObjectID], in context: NSManagedObjectContext) -> Needed {
        var needed = Needed()
        for objectID in records {
            guard let object = try? context.existingObject(with: objectID),
                  let entity = object.entity.name else { continue }
            if object.entity.attributesByName["id"] != nil, let id = object.value(forKey: "id") as? UUID {
                needed.ids[entity, default: []].insert(id)
            } else {
                needed.withoutID[entity, default: 0] += 1
            }
        }
        return needed
    }

    /// The reason the backup won't do, in the guide's words, or nil. `held` is the backup's
    /// IDs by entity. A record with no `id` is written to a backup under a new one (or not
    /// at all), so it can only be counted: for its entity, the backup must hold as many IDs
    /// as `notebookRows` (the notebook's distinct IDs plus its rows without one).
    static func problem(needed: Needed, held: [String: Set<UUID>], notebookRows: [String: Int]) -> String? {
        for entity in needed.ids.keys.sorted() {
            let missing = needed.ids[entity, default: []].subtracting(held[entity] ?? [])
            if !missing.isEmpty {
                return "The backup is missing \(missing.count) of the \(entity) records about to change. "
                    + "Nothing was changed."
            }
        }
        for entity in needed.withoutID.keys.sorted() {
            let backedUp = held[entity]?.count ?? 0
            let here = notebookRows[entity] ?? 0
            if backedUp < here {
                return "The backup holds \(backedUp) \(entity) records, the notebook \(here). Nothing was changed."
            }
        }
        return nil
    }

    /// For each entity: its distinct IDs plus its rows with no ID.
    private static func rowCounts(_ entities: [String], in context: NSManagedObjectContext) throws -> [String: Int] {
        let model = context.persistentStoreCoordinator?.managedObjectModel
        var counts: [String: Int] = [:]
        for entity in entities {
            do {
                let blank = NSFetchRequest<NSManagedObjectID>(entityName: entity)
                // The rows a backup holds: the private store's (`limitToNotebook`).
                BackupRestoreScope.limitToNotebook(blank, in: context)
                guard model?.entitiesByName[entity]?.attributesByName["id"] != nil else {
                    counts[entity] = try context.count(for: blank) // no IDs at all: every row
                    continue
                }
                blank.predicate = NSPredicate(format: "id == nil")
                let distinct = NSFetchRequest<NSDictionary>(entityName: entity)
                BackupRestoreScope.limitToNotebook(distinct, in: context)
                distinct.resultType = .dictionaryResultType
                distinct.propertiesToFetch = ["id"]
                distinct.returnsDistinctResults = true
                distinct.predicate = NSPredicate(format: "id != nil")
                counts[entity] = try context.fetch(distinct).count + context.count(for: blank)
            } catch {
                throw ClassroomShareRelease.BackupCheckError(
                    "Couldn't count the notebook's \(entity) records. Nothing was changed."
                )
            }
        }
        return counts
    }
}
