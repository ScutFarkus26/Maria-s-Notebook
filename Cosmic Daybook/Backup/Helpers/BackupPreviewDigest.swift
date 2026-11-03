// BackupPreviewDigest.swift
// What a restore preview needs from a backup — and nothing more.
//
// The preview used to decode the whole archive into a `BackupPayload` (every
// entry's bytes, then every record as a DTO) and look only at counts and IDs.
// The digest keeps just those: how many rows each entity type decoded to,
// every row's ID and `modifiedAt` (the merge analysis checks both against the
// store), and which types' entries didn't decode.
// `BackupImporter.decodePreview` fills it while the archive streams, one row
// at a time, so no entity's records are ever held together.

import Foundation

nonisolated struct BackupPreviewDigest: Sendable, Equatable {

    /// A lesson assignment as the merge analysis sees it.
    struct AssignmentReference: Sendable, Equatable {
        let id: UUID
        let lessonID: String
        let modifiedAt: Date?
    }

    /// One row as the analysis sees it: its ID, and the dates a Merge's
    /// newer-wins check weighs (`BackupRowDTO.rowModifiedAt`,
    /// `rowCompletedAt`; `BackupMergeRule`).
    struct RowStamp: Sendable, Equatable {
        let id: UUID
        let modifiedAt: Date?
        let completedAt: Date?

        init(id: UUID, modifiedAt: Date?, completedAt: Date? = nil) {
            self.id = id
            self.modifiedAt = modifiedAt
            self.completedAt = completedAt
        }

        init(_ row: any BackupRowDTO) {
            self.init(id: row.id, modifiedAt: row.rowModifiedAt, completedAt: row.rowCompletedAt)
        }
    }

    /// One entity's rows, gathered as they are decoded.
    struct EntityRows {
        let entityName: String
        fileprivate(set) var count = 0
        fileprivate(set) var stamps: [RowStamp] = []
        fileprivate(set) var assignments: [AssignmentReference] = []

        init(entityName: String) {
            self.entityName = entityName
        }

        /// Counts one decoded row and keeps what the analysis needs of it.
        mutating func add(_ row: any Sendable) {
            count += 1
            if let assignment = row as? LessonAssignmentDTO {
                assignments.append(AssignmentReference(
                    id: assignment.id, lessonID: assignment.lessonID, modifiedAt: assignment.modifiedAt
                ))
            } else if let row = row as? any BackupRowDTO {
                stamps.append(RowStamp(row))
            }
        }
    }

    /// Rows per archive entity name, for the types that decoded.
    private(set) var rowCounts: [String: Int] = [:]
    /// Every row's ID and `modifiedAt`, in archive order, per archive entity
    /// name (lesson assignments are kept below, with their lesson).
    private(set) var rowStamps: [String: [RowStamp]] = [:]
    private(set) var lessonAssignments: [AssignmentReference] = []
    /// The types whose entry in the archive didn't decode
    /// (`BackupImporter.DecodedArchive.skippedEntityNames`): a Replace leaves
    /// them as they are, and won't run without a required one.
    var skippedEntityNames: Set<String> = []
    /// The deprecated project-template sections. Archives never carry them;
    /// a payload built in memory can.
    private(set) var projectAssignmentTemplateCount = 0
    private(set) var projectTemplateWeekCount = 0
    private(set) var projectWeekRoleAssignmentCount = 0

    init() {}

    /// The digest of a whole payload, for a caller that already holds one.
    init(payload: BackupPayload) {
        for serialization in BackupWriter.entitySerializations {
            rowCounts[serialization.entityName] = serialization.count(payload)
        }
        for entity in BackupEntityTable.entities where entity.name != "LessonAssignment" {
            // An archive has no entry for a type with no rows.
            guard let rows = entity.rowsIn(payload), !rows.isEmpty else { continue }
            rowStamps[entity.name] = rows.map { RowStamp($0) }
        }
        lessonAssignments = payload.lessonAssignments.map {
            AssignmentReference(id: $0.id, lessonID: $0.lessonID, modifiedAt: $0.modifiedAt)
        }
        projectAssignmentTemplateCount = payload.projectAssignmentTemplates.count
        projectTemplateWeekCount = payload.projectTemplateWeeks.count
        projectWeekRoleAssignmentCount = payload.projectWeekRoleAssignments.count
    }

    /// How many rows `entityName` decoded to; 0 when it is absent or was skipped.
    func count(_ entityName: String) -> Int {
        rowCounts[entityName] ?? 0
    }

    /// The IDs of `entityName`'s rows, in archive order, duplicates kept.
    func ids(_ entityName: String) -> [UUID] {
        stamps(entityName).map(\.id)
    }

    /// `entityName`'s rows as the analysis sees them, in archive order,
    /// duplicates kept.
    func stamps(_ entityName: String) -> [RowStamp] {
        if entityName == "LessonAssignment" {
            return lessonAssignments.map { RowStamp(id: $0.id, modifiedAt: $0.modifiedAt) }
        }
        return rowStamps[entityName] ?? []
    }

    /// Keeps an entity whose every row decoded, replacing whatever an earlier
    /// entry of the same name left — as assigning the payload field did.
    mutating func record(_ rows: EntityRows) {
        rowCounts[rows.entityName] = rows.count
        if rows.entityName == "LessonAssignment" {
            lessonAssignments = rows.assignments
        } else {
            rowStamps[rows.entityName] = rows.stamps.isEmpty ? nil : rows.stamps
        }
    }
}
