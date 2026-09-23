import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

// MARK: - Orphan Detection
//
// An "orphan" is a classroom record sitting in the private store that belongs
// to no CKShare zone. CloudKit cannot export it, and one of them poisons the
// mirroring delegate for every subsequent import and export.
//
// Detection reads object IDs only (`.managedObjectIDResultType`), on a
// background context, so a pass never faults a row into memory and never
// registers anything with the view context.

extension SharedStoreZoneRepair {

    /// Everything one repair pass reads from: which entities count as
    /// classroom data, and the store and container to read them out of.
    /// Bundled so detection and repair cannot drift onto different stores.
    nonisolated struct RepairScope {
        let entityNames: [String]
        let store: NSPersistentStore
        let container: NSPersistentCloudKitContainer
        /// When set, only these rows are candidates (the rows history saw
        /// inserted since the clean watermark); `nil` means every row of
        /// `entityNames` — the launch / failed-history / manual full scan.
        var objectIDs: Set<NSManagedObjectID>?
    }

    /// Largest `SELF IN %@` list bound into one fetch.
    nonisolated static let candidateIDChunkSize = 500

    /// One candidate row: its object ID and the entity it belongs to.
    nonisolated struct Candidate: Sendable {
        let id: NSManagedObjectID
        let entityName: String
    }

    /// The outcome of one detection pass.
    nonisolated struct OrphanReport: Sendable {
        let orphanIDs: [NSManagedObjectID]
        let byEntity: [String: Int]
        /// True when CloudKit could not say which zone the candidates live in.
        /// The counts are then meaningless and the pass must not record a
        /// clean watermark.
        let failed: Bool

        static let empty = OrphanReport(orphanIDs: [], byEntity: [:], failed: false)
        static let unknown = OrphanReport(orphanIDs: [], byEntity: [:], failed: true)
    }

    /// Every record of the scoped entities in the private store, as IDs —
    /// or, when the scope carries `objectIDs`, just those of them that still
    /// exist in the private store. Must run on `context`'s queue.
    nonisolated static func fetchCandidateIDs(
        in scope: RepairScope,
        context: NSManagedObjectContext
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        for entityName in scope.entityNames {
            do {
                let ids = try fetchIDs(of: entityName, in: scope, context: context)
                candidates.reserveCapacity(candidates.count + ids.count)
                for id in ids {
                    candidates.append(Candidate(id: id, entityName: entityName))
                }
            } catch {
                let detail = error.localizedDescription
                let warnMsg = "Failed to fetch \(entityName) for zone check: \(detail)"
                Self.logger.warning("\(warnMsg, privacy: .public)")
            }
        }
        return candidates
    }

    /// The private-store IDs of `entityName` a pass must check. A scoped pass
    /// re-reads its inserted IDs through the store, so rows deleted since
    /// they were inserted, and rows that live in another store, drop out
    /// exactly as they would from a whole-table read.
    private nonisolated static func fetchIDs(
        of entityName: String,
        in scope: RepairScope,
        context: NSManagedObjectContext
    ) throws -> [NSManagedObjectID] {
        func request(_ predicate: NSPredicate?) -> NSFetchRequest<NSManagedObjectID> {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
            request.affectedStores = [scope.store]
            request.resultType = .managedObjectIDResultType
            request.predicate = predicate
            return request
        }
        guard let scoped = scope.objectIDs else {
            return try context.fetch(request(nil))
        }
        let ofEntity = scoped.filter { $0.entity.name == entityName }
        // An ID that can't say which store it came from can't be safely bound
        // (a primary key alone could match an unrelated row in this store), so
        // that entity falls back to the whole-table read.
        if ofEntity.contains(where: { $0.persistentStore == nil }) {
            return try context.fetch(request(nil))
        }
        let wanted = ofEntity.filter { $0.persistentStore?.identifier == scope.store.identifier }
        guard !wanted.isEmpty else { return [] }
        var ids: [NSManagedObjectID] = []
        let all = Array(wanted)
        for start in stride(from: 0, to: all.count, by: candidateIDChunkSize) {
            let chunk = Array(all[start..<min(start + candidateIDChunkSize, all.count)])
            ids.append(contentsOf: try context.fetch(request(NSPredicate(format: "SELF IN %@", chunk))))
        }
        return ids
    }

    /// `fetchCandidateIDs` on a fresh background context.
    nonisolated static func candidateIDs(in scope: RepairScope) async -> [Candidate] {
        let context = scope.container.newBackgroundContext()
        return await context.perform {
            fetchCandidateIDs(in: scope, context: context)
        }
    }

    /// Fetches every scoped classroom record in the private store and
    /// partitions out the ones that belong to no CKShare zone.
    nonisolated static func collectOrphans(in scope: RepairScope) async -> OrphanReport {
        let context = scope.container.newBackgroundContext()
        return await context.perform {
            let candidates = fetchCandidateIDs(in: scope, context: context)
            guard !candidates.isEmpty else { return .empty }

            let inShare: [NSManagedObjectID: CKShare]
            do {
                inShare = try scope.container.fetchShares(matching: candidates.map(\.id))
            } catch {
                Self.logger.error("fetchShares(matching:) failed: \(error.localizedDescription, privacy: .public)")
                return .unknown
            }

            var orphanIDs: [NSManagedObjectID] = []
            var byEntity: [String: Int] = [:]
            for candidate in candidates where inShare[candidate.id] == nil {
                orphanIDs.append(candidate.id)
                byEntity[candidate.entityName, default: 0] += 1
            }
            return OrphanReport(orphanIDs: orphanIDs, byEntity: byEntity, failed: false)
        }
    }
}
