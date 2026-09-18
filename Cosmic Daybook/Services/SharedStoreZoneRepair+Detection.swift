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
    }

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

    /// Every record of the scoped entities in the private store, as IDs.
    /// Must run on `context`'s queue.
    nonisolated static func fetchCandidateIDs(
        in scope: RepairScope,
        context: NSManagedObjectContext
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        for entityName in scope.entityNames {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
            request.affectedStores = [scope.store]
            request.resultType = .managedObjectIDResultType
            do {
                let ids = try context.fetch(request)
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
