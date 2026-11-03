import CoreData
import Foundation

/// Takes last year out of the classroom share: students who left in an earlier school year
/// and attendance from before this one (`ClassroomShareScope`). Everything stays in the
/// notebook; it only leaves the share, and so the assistants' iPhones.
///
/// Core Data can't unshare a record, and moving a shared record with `share(_:to:)` broke
/// the export in 2026-09 (`share-move incident`). So each record is **copied**: an identical
/// object (same `id`, every attribute) goes into the private default zone, and only once
/// iCloud itself has the copy is the shared original deleted. In batches, each in five steps:
///
/// 1. insert the copies and save;
/// 2. confirm on the CloudKit server that every copy is there;
/// 3. check every copy still exists here, and bring over anything the original changed since
///    (a record another device deleted meanwhile goes, copy and all, once the server
///    confirms it: `+Vanished`);
/// 4. delete the originals and save;
/// 5. confirm on the server that the originals are gone.
///
/// iCloud never holds fewer than one copy, and the guide's other devices receive a copy
/// before the delete, so they never see a child missing (with `DedupShareBoundary` and
/// `OrphanStudentGrace` as the second line). A run stopped anywhere leaves at most both
/// copies; the next run finds the private copy (a "twin") and only deletes. One stopped
/// after its last deletes leaves nothing to plan; finishing it only checks iCloud (`+Finish`).
/// A twin whose shared original belongs in the share after all (the child came back before
/// the run was finished) goes instead, and the shared original stays (`+Twins`).
///
/// This file is the plan — pure, so it is tested without CloudKit. `+Run` carries it out.
nonisolated enum ClassroomShareRelease {

    /// One record of the share's student types, as the planner sees it.
    struct Row: Sendable, Equatable {
        let objectID: NSManagedObjectID
        /// "Student" or "AttendanceRecord".
        let entity: String
        /// The record's own `id`: copies share it.
        let recordID: UUID?
        /// The student the record is about, normalized (`ClassroomShareScope.normalizedID`).
        let studentKey: String
        /// In the pinned share (per `fetchShares(matching:)`), as opposed to in no share.
        let isShared: Bool
        /// Belongs in this school year's share.
        let belongs: Bool
        /// Why a backup can't hold this record, or nil. Such a record is never planned: the
        /// run's backup check would refuse every time. The preview names it instead.
        var backupGap: BackupGap?
        /// A mark dated this school year (`ClassroomShareScope.isThisYear`); false for a
        /// student. One that still doesn't belong is of a child no longer in the notebook.
        var datedThisYear = false
    }

    /// What keeps a record out of a backup: `BackupServiceHelpers.toDTOs` leaves out a
    /// record with no `id`, and a mark with no date or a `studentID` that isn't an id.
    enum BackupGap: Sendable, Equatable {
        case noID, noDate, noChild
    }

    /// One record to take out of the share: the shared original(s) and the private copy
    /// that stays, either made by this run or found from an earlier one.
    struct Move: Sendable, Equatable {
        let entity: String
        let studentKey: String
        /// The shared original the copy is made from (and whose values it must match).
        let source: NSManagedObjectID
        /// A private copy an earlier run already made, or nil: this run makes one.
        let existingTwin: NSManagedObjectID?
        /// Every shared row of this record: all are deleted once the copy is confirmed.
        let sharedRows: [NSManagedObjectID]
    }

    /// A record a stopped run left on both sides whose shared original belongs in the share
    /// after all: the child came back before the run was finished, or the school-year start
    /// moved earlier. The shared original stays; its private copies go (`+Twins`).
    struct TwinCleanup: Sendable, Equatable {
        let entity: String
        let studentKey: String
        /// The shared original, which stays.
        let shared: NSManagedObjectID
        /// The private copies a stopped run made, which go.
        let twins: [NSManagedObjectID]
    }

    /// Moves carried out together: one departed child with all her records, or a slice of
    /// earlier-year attendance. Or, in batches of their own, a slice of twin cleanups.
    struct Batch: Sendable, Equatable {
        /// The departed child the batch is about, or nil for earlier-year attendance.
        let studentKey: String?
        let moves: [Move]
        /// Records a stopped run left twice that belong in the share after all. A batch
        /// holds these or moves, never both.
        var twinCleanups: [TwinCleanup] = []
    }

    /// Earlier-year attendance of children still in the share goes in slices this size.
    static let attendanceSliceSize = 500
    /// A canary with no departed child is this many records.
    static let canarySliceSize = 25

    // MARK: - Planning

    /// The moves `rows` call for, in batches: the smallest departed child first (the
    /// canary), then the other children, then earlier-year attendance in slices. Last come
    /// the twins of records that belong after all (`twinCleanups`), in slices too.
    static func plan(_ rows: [Row]) -> [Batch] {
        var batches = moveBatches(moves(in: rows))
        let cleanups = twinCleanups(in: rows)
        var start = 0
        while start < cleanups.count {
            let end = min(start + attendanceSliceSize, cleanups.count)
            batches.append(Batch(studentKey: nil, moves: [], twinCleanups: Array(cleanups[start..<end])))
            start = end
        }
        return batches
    }

    private static func moveBatches(_ moves: [Move]) -> [Batch] {
        guard !moves.isEmpty else { return [] }

        let departed = Set(moves.filter { $0.entity == "Student" }.map(\.studentKey))
        var byChild: [String: [Move]] = [:]
        var older: [Move] = []
        for move in moves {
            if departed.contains(move.studentKey) {
                byChild[move.studentKey, default: []].append(move)
            } else {
                older.append(move)
            }
        }

        var batches = byChild.map { key, moves in
            Batch(studentKey: key, moves: moves.sorted(by: moveOrder))
        }
        .sorted { ($0.moves.count, $0.studentKey ?? "") < ($1.moves.count, $1.studentKey ?? "") }

        older.sort(by: moveOrder)
        if batches.isEmpty, older.count > canarySliceSize {
            // No child to lead with: a small slice goes first.
            batches.append(Batch(studentKey: nil, moves: Array(older.prefix(canarySliceSize))))
            older.removeFirst(canarySliceSize)
        }
        var start = 0
        while start < older.count {
            let end = min(start + attendanceSliceSize, older.count)
            batches.append(Batch(studentKey: nil, moves: Array(older[start..<end])))
            start = end
        }
        return batches
    }

    /// Every record with a shared row outside the scope, grouped by its `id` so an earlier
    /// run's private copy is found and reused rather than copied again.
    static func moves(in rows: [Row]) -> [Move] {
        var moves: [Move] = []
        for group in groupedByRecord(rows) {
            let shared = group.filter(\.isShared).sorted(by: rowOrder)
            // Only records the share holds and shouldn't: a copy's `belongs` matches its
            // original's, since both carry the same values. One a backup can't hold stays
            // (`leftShared`).
            guard let source = shared.first, !source.belongs, source.backupGap == nil else { continue }
            let twin = group.filter { !$0.isShared }.sorted(by: rowOrder).first
            moves.append(Move(
                entity: source.entity,
                studentKey: source.studentKey,
                source: source.objectID,
                existingTwin: twin?.objectID,
                sharedRows: shared.map(\.objectID)
            ))
        }
        return moves.sorted(by: moveOrder)
    }

    /// Every record whose shared original belongs this year and has a private copy beside
    /// it, which only a stopped run makes (bug hunt 2026-11-02, #38). No move plans one, its
    /// original belonging, and dedup leaves a record on both sides of the share alone
    /// (`DedupShareBoundary`): without this both copies stayed for good, and an edit to the
    /// private one never reached the assistants.
    static func twinCleanups(in rows: [Row]) -> [TwinCleanup] {
        var cleanups: [TwinCleanup] = []
        for group in groupedByRecord(rows) {
            let shared = group.filter(\.isShared).sorted(by: rowOrder)
            // One a backup can't hold stays as it is: the run's backup check would refuse.
            guard let source = shared.first, source.belongs, source.backupGap == nil else { continue }
            let twins = group.filter { !$0.isShared }.sorted(by: rowOrder)
            guard !twins.isEmpty else { continue }
            cleanups.append(TwinCleanup(
                entity: source.entity, studentKey: source.studentKey, shared: source.objectID,
                twins: twins.map(\.objectID)
            ))
        }
        return cleanups.sorted { lhs, rhs in
            if lhs.entity != rhs.entity { return lhs.entity == "Student" }
            return lhs.shared.uriRepresentation().absoluteString < rhs.shared.uriRepresentation().absoluteString
        }
    }

    /// The rows by record (entity and `id`), so a record's shared original and a stopped
    /// run's private copy of it are seen together. A row without an id can't have a copy; it
    /// is its own group.
    private static func groupedByRecord(_ rows: [Row]) -> [[Row]] {
        var groups: [String: [Row]] = [:]
        for row in rows {
            let key = row.recordID.map { "\(row.entity)|\($0.uuidString)" }
                ?? "\(row.entity)|\(row.objectID.uriRepresentation().absoluteString)"
            groups[key, default: []].append(row)
        }
        return Array(groups.values)
    }

    /// The shared records that don't belong but stay in the share, because a backup can't
    /// hold them (`Row.backupGap`), for the preview to name.
    static func leftShared(in rows: [Row]) -> [Row] {
        var seen = Set<String>()
        return rows.filter { $0.isShared && !$0.belongs && $0.backupGap != nil }
            .sorted(by: rowOrder)
            .filter { row in
                guard let id = row.recordID else { return true }
                return seen.insert("\(row.entity)|\(id.uuidString)").inserted
            }
    }

    private static func rowOrder(_ lhs: Row, _ rhs: Row) -> Bool {
        lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }

    /// Students before their attendance, then a stable order.
    private static func moveOrder(_ lhs: Move, _ rhs: Move) -> Bool {
        if lhs.entity != rhs.entity { return lhs.entity == "Student" }
        return lhs.source.uriRepresentation().absoluteString < rhs.source.uriRepresentation().absoluteString
    }
}
