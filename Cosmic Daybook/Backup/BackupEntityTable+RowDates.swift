// BackupEntityTable+RowDates.swift
// Each backed-up row type's conformance to `BackupRowDTO`: its record's
// `id`, and when the record last changed, for a Merge's newer-wins check
// (`BackupMergeRule`, `BackupRestoreRun.keepingNewer`; bug hunt 2026-11-02, #1).

import CoreData
import Foundation

// Each DTO already has `id: UUID`; conforming here is what lets its table row
// compile. `rowModifiedAt` is the date `BackupMergeRule.changeDateAttribute`
// names for its entity: `modifiedAt`, or a note's and a reminder's
// `updatedAt`. The rest have none, and a Merge takes the backup's row for
// them (but a to-do done here stays done, `rowCompletedAt`).
// `BackupMergeNewerWinsTests` checks every type against the model.
nonisolated extension SequenceTrackDTO: BackupRowDTO { var rowModifiedAt: Date? { nil } }
nonisolated extension DocumentDTO: BackupRowDTO { var rowModifiedAt: Date? { nil } }
nonisolated extension SupplyDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension ProcedureDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension ScheduleSlotDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension IssueDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension IssueActionDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension DevelopmentSnapshotDTO: BackupRowDTO { var rowModifiedAt: Date? { nil } }
nonisolated extension TodoItemDTO: BackupRowDTO {
    var rowModifiedAt: Date? { nil }
    /// When the backup's to-do was done; nil when it wasn't.
    var rowCompletedAt: Date? { isCompleted ? completedAt : nil }
}
nonisolated extension TodayAgendaOrderDTO: BackupRowDTO { var rowModifiedAt: Date? { nil } }
nonisolated extension PlanningRecommendationDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension ResourceDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension GoingOutChecklistItemDTO: BackupRowDTO { var rowModifiedAt: Date? { nil } }
nonisolated extension StoryDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension BookClubPacketDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension AlbumHighlightDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }
nonisolated extension AlbumPageInkDTO: BackupRowDTO { var rowModifiedAt: Date? { modifiedAt } }

/// A `ModelRow`'s change date (`modifiedAt`, or `updatedAt` for the types
/// `BackupMergeRule.updatedAtEntityNames` names) and, for a type a Merge
/// judges by when it was done, its done date while it is done.
nonisolated extension ModelRow {
    var rowModifiedAt: Date? {
        let key = BackupMergeRule.updatedAtEntityNames.contains(Kind.spec.entityName) ? "updatedAt" : "modifiedAt"
        return if case .date(let date)? = values[key] { date } else { nil }
    }

    var rowCompletedAt: Date? {
        guard BackupMergeRule.completionEntityNames.contains(Kind.spec.entityName),
              case .bool(true)? = values[BackupMergeRule.doneFlag],
              case .date(let date)? = values["completedAt"] else { return nil }
        return date
    }
}

/// How a Merge weighs a backup row against the record already here: newer
/// wins (Danny's choice, bug hunt 2026-11-02 #1). The restore
/// (`BackupRestoreRun.keepingNewer`) and its preview (`BackupPreviewAnalyzer`)
/// both ask here, so what the preview counts as kept is what the restore keeps.
nonisolated enum BackupMergeRule {

    /// The record already here, as the rule sees it.
    struct Stored: Sendable, Equatable {
        /// When it last changed (`changeDateAttribute`); nil when its entity
        /// has no such date or the record has none.
        var changedAt: Date?
        /// When it was done, for an entity in `completionEntityNames`; nil
        /// otherwise, and for one that isn't done.
        var completedAt: Date?

        /// Either date, keeping the later of each: synced copies that share
        /// an `id` stand together.
        func latest(with other: Stored) -> Stored {
            Stored(
                changedAt: Self.later(changedAt, other.changedAt),
                completedAt: Self.later(completedAt, other.completedAt)
            )
        }

        private static func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
            guard let lhs, let rhs else { return lhs ?? rhs }
            return max(lhs, rhs)
        }
    }

    /// The entities whose records carry an `updatedAt` that every edit sets
    /// and no `modifiedAt`: notes (the editor, the repository, quick capture
    /// and every other writer set it).
    /// Other dates were checked and left out: a work record's
    /// `lastTouchedAt` isn't set by every edit (the work editor leaves it,
    /// and some paths clear it), and a presentation's `followUpUpdatedAt`
    /// dates only its follow-up.
    static let updatedAtEntityNames: Set<String> = ["Note"]

    /// The entities whose done date a Merge stands by: a to-do done here
    /// is never reopened by a backup row that isn't done, or was done
    /// earlier. A to-do has no change date (none is added: a model change
    /// the 2026-11 plan rules out), so this is all a Merge can judge it by.
    static let completionEntityNames: Set<String> = ["TodoItem"]

    /// The attribute that dates every change to `entity`'s records: its
    /// `modifiedAt`, or `updatedAt` for those in `updatedAtEntityNames`;
    /// nil when it has neither. A Merge takes the backup's row for those
    /// (`BackupRowDTO.rowModifiedAt` is nil for them).
    static func changeDateAttribute(of entity: NSEntityDescription) -> String? {
        if entity.attributesByName["modifiedAt"] != nil { return "modifiedAt" }
        if let name = entity.name, updatedAtEntityNames.contains(name), entity.attributesByName["updatedAt"] != nil {
            return "updatedAt"
        }
        return nil
    }

    /// `completedAt`, for an entity in `completionEntityNames`.
    static func completionAttribute(of entity: NSEntityDescription) -> String? {
        guard let name = entity.name, completionEntityNames.contains(name),
              entity.attributesByName["completedAt"] != nil,
              entity.attributesByName[doneFlag] != nil else { return nil }
        return "completedAt"
    }

    /// Whether a to-do is done. Its done date counts only while it is: an
    /// untick that missed clearing the date (a same-source merge copies the
    /// flag alone) mustn't keep it open against the backup.
    static let doneFlag = "isCompleted"

    /// The columns a Merge reads for one entity's records, and the dates
    /// they give: the restore's id map (`BackupEntityIndex`) and the
    /// preview (`BackupPreviewAnalyzer`) fetch the same ones.
    struct Columns {
        let change: String?
        let completion: String?

        init(_ entity: NSEntityDescription) {
            change = BackupMergeRule.changeDateAttribute(of: entity)
            completion = BackupMergeRule.completionAttribute(of: entity)
        }

        /// What to fetch besides `id` (none for an entity with no such dates).
        var keys: [String] {
            [change, completion, completion.map { _ in BackupMergeRule.doneFlag }].compactMap { $0 }
        }

        /// A record's dates from a dictionary fetch of `keys`; nil when it has neither.
        func stored(from row: NSDictionary) -> Stored? {
            let isDone = row[BackupMergeRule.doneFlag] as? Bool == true
            let stamp = Stored(
                changedAt: change.flatMap { row[$0] as? Date },
                completedAt: isDone ? completion.flatMap { row[$0] as? Date } : nil
            )
            return stamp.changedAt == nil && stamp.completedAt == nil ? nil : stamp
        }
    }

    /// Whether a Merge leaves the record here as it is rather than take a
    /// backup row with these dates:
    /// - it changed after the row (`changedAt` later than `rowChangedAt`).
    ///   No date on either side means the row is taken, except where
    ///   `keepsDatedOverDateless` (the names people set, since 2026-10-29),
    ///   where a dated record stands against a dateless row;
    /// - it is done, and the row isn't, or was done earlier.
    static func keepsStored(
        _ stored: Stored,
        rowChangedAt: Date?,
        rowCompletedAt: Date?,
        keepsDatedOverDateless: Bool = false
    ) -> Bool {
        if let storedAt = stored.changedAt,
           rowChangedAt.map({ isLater(storedAt, than: $0) }) ?? keepsDatedOverDateless {
            return true
        }
        if let doneAt = stored.completedAt, rowCompletedAt.map({ isLater(doneAt, than: $0) }) ?? true {
            return true
        }
        return false
    }

    /// Whether a stored date is later than a backup row's, to the precision
    /// the backup kept it: milliseconds since 2026-11 (`BackupDateCoding`),
    /// whole seconds before. The archive cuts the rest off, so a record no
    /// one has touched since the backup is a little later than its own row;
    /// counted as newer, every such record showed as kept in the preview.
    /// (A row made in memory, as tests make them, has the stored date exactly.)
    static func isLater(_ stored: Date, than row: Date) -> Bool {
        let rowTime = row.timeIntervalSinceReferenceDate
        // A whole second is a backup from before 2026-11 (or, one time in a
        // thousand, a later one's date that fell on the second).
        let precision = rowTime.rounded(.down) == rowTime ? 1 : 0.002
        return stored.timeIntervalSinceReferenceDate - rowTime >= precision
    }
}
