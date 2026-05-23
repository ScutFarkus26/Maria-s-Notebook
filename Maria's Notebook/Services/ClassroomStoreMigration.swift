import Foundation
import CoreData
import CloudKit
import OSLog

/// One-shot migration that moves all classroom-level records from the
/// `.shared`-scope shared store into the `.private`-scope private store.
///
/// **Why this exists.** Earlier versions of Maria's Notebook routed classroom
/// data (Students, Lessons, Tracks, …) to a Core Data store configured with
/// `databaseScope = .shared`. That's the wrong scope for an owner sharing
/// data: `.shared` is the **receive** side of CloudKit sharing — it holds
/// records that other users have shared *with* this user. The **share** side
/// (data the user owns and intends to share via `container.share(_:to:)`)
/// must live in a `.private`-scope store. `container.share` errors out
/// otherwise:
///
/// > Failed to assign an object to a record zone … objects that exist in the
/// > 'wrong' store must be cloned (and their originals deleted) after which
/// > they can be assigned to the correct store. (`NSCocoaErrorDomain 134060`)
///
/// This migration moves the lead-guide-owned classroom data into the private
/// store so the canonical sharing flow works. Assistants who have *accepted*
/// a share keep their data exactly where it is — for them, `.shared` is the
/// correct destination.
///
/// **Strategy.** Two-phase clone-and-delete on a **background context**:
///   1. **Clone** every classroom record from the shared store into the
///      private store, copying every attribute via primitive accessors.
///      Build an `oldObjectID → newObject` map.
///   2. **Rewire** Core Data relationships on the new records by looking up
///      each old relationship target in the map. If any target falls outside
///      the classroom-entity set, abort: that signals a cross-config
///      relationship that would silently drop data.
///   3. **Delete** the originals.
///   4. **Save** in one transaction. On failure, the context is rolled back
///      and no completion flag is set — the next launch retries.
///   5. **Verify** the shared store is empty of classroom records before
///      setting the completion flag.
///
/// **Off-main.** All heavy work runs on a `newBackgroundContext()` so the
/// MainActor-bound `viewContext` stays available for view fetches during
/// migration. With `automaticallyMergesChangesFromParent` enabled on the
/// view context, the UI picks up the moved records automatically after save.
///
/// **Idempotent.** Guarded by a UserDefaults flag. The flag is only set when
/// we can prove migration is unnecessary on this device (assistant role, or
/// private store already holds classroom records, or shared store is verified
/// empty after a positive migration). A freshly-installed lead-guide device
/// whose CloudKit hasn't synced yet defers completion until a later launch —
/// see the `totalCloned == 0` branch.
enum ClassroomStoreMigration {

    private static let completedKey = UserDefaultsKeys.classroomStoreMigrationV1Complete
    private static let logger = Logger.migration

    /// Whether the migration has already completed on this device.
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Runs the migration if needed. Awaitable; the actual clone/rewire/save
    /// work runs on a background context to keep the main thread responsive.
    @MainActor
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        guard !hasCompleted else { return }
        guard coreDataStack.isCloudKitActive else {
            logger.info("ClassroomStoreMigration: CloudKit not active, skipping")
            return
        }
        guard let sharedStore = coreDataStack.sharedPersistentStore,
              let privateStore = coreDataStack.privatePersistentStore else {
            logger.info("ClassroomStoreMigration: stores not available, skipping")
            return
        }

        // Assistant short-circuit. ClassroomRepository is MainActor-bound,
        // so we run this check on the view context up front rather than
        // crossing isolation into the background context.
        let repo = ClassroomRepository(context: coreDataStack.viewContext)
        if let membership = repo.fetchCurrentMembership(), membership.role == .assistant {
            UserDefaults.standard.set(true, forKey: completedKey)
            logger.info("ClassroomStoreMigration: skipping on assistant device — classroom data correctly lives in shared store")
            return
        }

        let bgContext = coreDataStack.newBackgroundContext()
        await run(
            context: bgContext,
            sharedStore: sharedStore,
            privateStore: privateStore
        )
    }

    /// Internal runner — exposed for testing. Performs the migration on the
    /// supplied context's own queue via `context.perform`.
    static func run(
        context: NSManagedObjectContext,
        sharedStore: NSPersistentStore,
        privateStore: NSPersistentStore
    ) async {
        // NSPersistentStore is thread-safe through its coordinator's queue
        // but lacks formal Sendable conformance. Capture it as
        // nonisolated(unsafe) so the @Sendable closure passed to
        // `context.perform` doesn't complain. NSManagedObjectContext is
        // already Sendable in the current SDK.
        nonisolated(unsafe) let sharedRef = sharedStore
        nonisolated(unsafe) let privateRef = privateStore
        await context.perform {
            performRun(context: context, sharedStore: sharedRef, privateStore: privateRef)
        }
    }

    private static func performRun(
        context: NSManagedObjectContext,
        sharedStore: NSPersistentStore,
        privateStore: NSPersistentStore
    ) {
        let entityNames = CoreDataStack.sharedEntityNames.sorted()
        let start = Date()

        // Phase 1: clone all classroom records into the private store.
        // We DON'T rewire relationships yet — set them only after every
        // record has its new equivalent in the map so cross-references
        // resolve.
        var oldToNew: [NSManagedObjectID: NSManagedObject] = [:]
        var oldRecords: [NSManagedObject] = []
        var perEntityCounts: [String: Int] = [:]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [sharedStore]
            do {
                let records = try context.fetch(request)
                for old in records {
                    let new = clone(old, context: context, privateStore: privateStore)
                    oldToNew[old.objectID] = new
                    oldRecords.append(old)
                }
                if !records.isEmpty {
                    perEntityCounts[entityName] = records.count
                }
            } catch {
                logger.error("ClassroomStoreMigration: fetch failed for \(entityName, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }

        let totalCloned = oldRecords.count
        if totalCloned == 0 {
            // Zero records in the shared store. Marking complete here could
            // strand records that haven't synced yet on a freshly-installed
            // device. Only mark complete if we have *positive* evidence the
            // migration is unnecessary on this device:
            //
            //   - The private store already holds classroom records — either
            //     a prior run completed, or this is a fresh install on the
            //     post-refactor build that wrote directly to private.
            //
            // Otherwise leave the flag clear; the next launch will retry
            // once CloudKit has had a chance to download data.
            let privateClassroomCount = countClassroomRecords(
                in: privateStore,
                context: context,
                entityNames: entityNames
            )
            if privateClassroomCount > 0 {
                UserDefaults.standard.set(true, forKey: completedKey)
                logger.info("ClassroomStoreMigration: shared store empty, private store has \(privateClassroomCount, privacy: .public) classroom record(s); marking complete")
            } else {
                logger.info("ClassroomStoreMigration: both stores empty — will retry next launch after CloudKit sync settles")
            }
            return
        }

        // Phase 2: walk relationships on each old record and rewire its new
        // clone to point at the corresponding new clones.
        var hasUnmappableTarget = false
        for old in oldRecords {
            guard let new = oldToNew[old.objectID] else { continue }
            let dropped = rewireRelationships(from: old, to: new, mapping: oldToNew)
            if dropped { hasUnmappableTarget = true }
        }

        if hasUnmappableTarget {
            // Surface this loudly in dev; in production, rollback rather
            // than committing silent data loss. The classroom-entity set is
            // intended to be self-contained — a relationship target outside
            // it means a future contributor added a cross-config relationship
            // without expanding this migration to handle it.
            #if DEBUG
            fatalError("ClassroomStoreMigration: a classroom-entity relationship targets an entity outside the classroom set. Expand CoreDataStack.sharedEntityNames to cover it, or restructure the relationship.")
            #else
            logger.error("ClassroomStoreMigration: dropped one or more cross-config relationships during rewire; rolling back to avoid silent data loss")
            context.rollback()
            return
            #endif
        }

        // Phase 3: delete the originals.
        for old in oldRecords {
            context.delete(old)
        }

        // Phase 4: save. On failure, roll back and let the next launch retry.
        do {
            try context.save()
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            logger.info("ClassroomStoreMigration: migrated \(totalCloned, privacy: .public) record(s) shared→private in \(elapsed, privacy: .public)s; per-entity=\(perEntityCounts, privacy: .public)")

            // Phase 5: verify shared store is now empty of classroom
            // records. Don't mark complete if anything was left behind — the
            // next launch will retry to sweep them in.
            let remainingInShared = countClassroomRecords(in: sharedStore, context: context, entityNames: entityNames)
            if remainingInShared > 0 {
                logger.error("ClassroomStoreMigration: \(remainingInShared, privacy: .public) record(s) remain in shared store after migration — not marking complete, will retry next launch")
                return
            }
            UserDefaults.standard.set(true, forKey: completedKey)
        } catch {
            let ns = error as NSError
            logger.error("ClassroomStoreMigration: save failed — domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) description=\(ns.localizedDescription, privacy: .public). Rolling back.")
            context.rollback()
        }
    }

    private static func countClassroomRecords(
        in store: NSPersistentStore,
        context: NSManagedObjectContext,
        entityNames: [String]
    ) -> Int {
        var total = 0
        for name in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.affectedStores = [store]
            if let count = try? context.count(for: request) {
                total += count
            }
        }
        return total
    }

    // MARK: - Internals

    /// Inserts a new managed object into the private store with the same
    /// attribute values as `old`. Uses standard KVC accessors (not primitive)
    /// because several classroom entities have transformable attributes
    /// (`Student.nextLessons`, `Story.themes`, `BookClubPacket.themes`,
    /// `Resource.tags`, etc.) and `allowsExternalBinaryDataStorage` blobs.
    /// Primitive accessors bypass the value transformer and external-blob
    /// faulting, which silently produces null/garbled values that make
    /// downstream fetches drop the cloned records. Relationships are
    /// intentionally NOT copied here — they're set in Phase 2 once every
    /// clone exists.
    private static func clone(
        _ old: NSManagedObject,
        context: NSManagedObjectContext,
        privateStore: NSPersistentStore
    ) -> NSManagedObject {
        let new = NSManagedObject(entity: old.entity, insertInto: context)
        context.assign(new, to: privateStore)
        for (name, _) in old.entity.attributesByName {
            new.setValue(old.value(forKey: name), forKey: name)
        }
        return new
    }

    /// Walks `old`'s relationships and sets them on `new` using the
    /// `mapping` to translate old object IDs to new clones. Inverses are
    /// applied automatically by Core Data, so we only need to set each side.
    ///
    /// Returns `true` if any relationship target was missing from the
    /// mapping — i.e. the relationship points to a non-classroom entity that
    /// the migration can't move. Callers should treat this as a fatal
    /// migration failure rather than silently dropping the relationship.
    private static func rewireRelationships(
        from old: NSManagedObject,
        to new: NSManagedObject,
        mapping: [NSManagedObjectID: NSManagedObject]
    ) -> Bool {
        var dropped = false
        for (name, rel) in old.entity.relationshipsByName {
            if rel.isToMany {
                guard let oldSet = old.value(forKey: name) as? NSSet else { continue }
                let newSet = NSMutableSet()
                for case let item as NSManagedObject in oldSet {
                    if let mapped = mapping[item.objectID] {
                        newSet.add(mapped)
                    } else {
                        dropped = true
                        logger.warning("ClassroomStoreMigration: relationship \(name, privacy: .public) on \(old.entity.name ?? "?", privacy: .public) targets non-classroom entity \(item.entity.name ?? "?", privacy: .public)")
                    }
                }
                new.setValue(newSet, forKey: name)
            } else {
                if let oldTarget = old.value(forKey: name) as? NSManagedObject {
                    if let mapped = mapping[oldTarget.objectID] {
                        new.setValue(mapped, forKey: name)
                    } else {
                        dropped = true
                        logger.warning("ClassroomStoreMigration: relationship \(name, privacy: .public) on \(old.entity.name ?? "?", privacy: .public) targets non-classroom entity \(oldTarget.entity.name ?? "?", privacy: .public)")
                    }
                }
            }
        }
        return dropped
    }
}
