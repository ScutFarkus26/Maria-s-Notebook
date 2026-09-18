// DataCleanupService+ShelfDeduplication.swift
//
// The supply shelf, its adjustment history, and the resource library, folded
// back to one row per logical record.
//
// Every classroom entity is assigned to *both* store configurations
// (`CoreDataStack.assignEntitiesToConfigurations`), so an unscoped fetch
// legitimately spans private + shared — and `ClassroomStoreMigration.clone`
// copies every attribute **including `id`** when it moves a row from shared to
// private. Each device minted its own clone and the clones then synced to each
// other, which is why the guide's three supplies were reading back six times
// and her two resources six. Students and lessons took exactly the same hit and
// read clean only because they were already in `deduplicateAllModels`.
//
// Split from +Deduplication.swift, which is already well past the file limit.

import CoreData
import Foundation
import os

nonisolated extension DataCleanupService {

    /// Folds cloned supplies, supply transactions and resources.
    ///
    /// Order matters: supplies run first, so the transactions their duplicates
    /// carried are re-parented onto the survivor before the transaction pass
    /// reads the table. Deliberately absent from this list —
    /// `ClassroomMembership`, where deleting a row can break sharing itself.
    ///
    /// Every other entity exposed to the same clone (Procedure, Story,
    /// Schedule, GoingOut, ClassroomJob, BookClubPacket, TodoTemplate,
    /// LessonAttachment, CalendarNote) holds 0–1 rows today, so none of them
    /// can have a duplicate to fold yet.
    ///
    /// Returns only the types that actually shrank, matching
    /// `deduplicateAllModels`, and writes nothing at all when there is nothing
    /// to fold — the generic pass reads just the `id` column first. That
    /// restraint matters here more than most: these deletes sync, and on a
    /// shared classroom they reach the assistant's device too.
    static func shelfDuplicates(
        in context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> [String: Int] {
        var results: [String: Int] = [:]
        results["Supply"] = deduplicate(
            CDSupply.self, using: context, container: container, scope: scope, merge: mergeSupply
        )
        results["SupplyTransaction"] = deduplicate(
            CDSupplyTransaction.self, using: context, container: container, scope: scope
        )
        // Resource holds no relationships, so there is nothing to rescue first.
        results["Resource"] = deduplicate(CDResource.self, using: context, container: container, scope: scope)
        return results.filter { $0.value > 0 }
    }

    /// Folds a duplicate supply onto the canonical row.
    ///
    /// `Supply.transactions` is a **Cascade** relationship, so deleting the
    /// duplicate would take its adjustment history with it and the running
    /// total would be left with nothing to explain it. Re-parent every
    /// transaction first — writing both the relationship and the `supplyID`
    /// string the readers use — the way `mergeLessonAssignment` rescues notes.
    ///
    /// The two rows are clones of one logical supply, so they agree on almost
    /// everything; where the counts have drifted apart the canonical row's
    /// count stands. The merged history is what makes that recoverable, which
    /// is the other reason it has to survive.
    private static func mergeSupply(canonical: CDSupply, duplicate: CDSupply) {
        // `transactions` is in the model but not declared on the Swift class,
        // so it is reached by key.
        let moving = (duplicate.value(forKey: "transactions") as? NSSet)?.count ?? 0
        var existingIDs = Set(
            ((canonical.value(forKey: "transactions") as? NSSet) as? Set<CDSupplyTransaction>)?
                .compactMap(\.id) ?? []
        )
        let canonicalID = canonical.id?.uuidString ?? ""
        mergeNSSetRelationship(
            from: duplicate.value(forKey: "transactions") as? NSSet,
            addTo: canonical,
            relationshipKey: "transactions",
            existingIDs: &existingIDs,
            setter: { (transaction: CDSupplyTransaction) in
                transaction.supply = canonical
                transaction.supplyID = canonicalID
            }
        )
        if canonical.notes.trimmed().isEmpty, !duplicate.notes.trimmed().isEmpty {
            canonical.notes = duplicate.notes
        }
        logSupplyMerge(canonical: canonical, duplicate: duplicate, movedTransactions: moving)
    }

    /// Notice level, not info: this pass deletes a row that has already synced,
    /// and the log is the guide's only record of what it folded together.
    private static func logSupplyMerge(
        canonical: CDSupply, duplicate: CDSupply, movedTransactions: Int
    ) {
        let name = canonical.name
        let quantities = canonical.currentQuantity == duplicate.currentQuantity
            ? ""
            : " (kept \(canonical.currentQuantity) on hand over \(duplicate.currentQuantity))"
        logger.notice(
            """
            Merged a duplicate copy of supply \(name, privacy: .public): moved \
            \(movedTransactions, privacy: .public) transaction(s)\(quantities, privacy: .public)
            """
        )
    }
}
