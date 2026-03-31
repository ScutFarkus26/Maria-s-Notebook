import Foundation
import CoreData

// MARK: - Conflict Detection

extension EnhancedBackupService {

    /// Detects potential conflicts between backup data and current database state
    /// This helps identify issues before attempting a restore operation
    func detectRestoreConflicts(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext,
        mode: RestoreMode
    ) async throws -> [CloudSyncConflictResolver.Conflict] {
        var conflicts: [CloudSyncConflictResolver.Conflict] = []

        // Replace mode intentionally overwrites everything, so merge conflicts do not apply.
        guard mode == .merge else {
            return []
        }

        let backupCounts = getPayloadEntityCounts(payload)
        let localCounts = try currentEntityCounts(viewContext: viewContext)
        let localInfo = makeLocalBackupInfo(entityCounts: localCounts)
        let incomingInfo = makeIncomingBackupInfo(entityCounts: backupCounts)

        // Count divergence can indicate drift between devices.
        let localTotal = localCounts.values.reduce(0, +)
        let incomingTotal = backupCounts.values.reduce(0, +)
        let totalDiff = abs(localTotal - incomingTotal)
        if max(localTotal, incomingTotal) > 0 {
            let ratio = Double(totalDiff) / Double(max(localTotal, incomingTotal))
            if ratio > BackupConstants.entityDiffThreshold {
                conflicts.append(
                    CloudSyncConflictResolver.Conflict(
                        localBackup: localInfo,
                        remoteBackup: incomingInfo,
                        conflictType: .divergentHistory,
                        description: "Database and backup differ significantly "
                            + "in record counts (\(localTotal) vs \(incomingTotal))."
                    )
                )
            }
        }

        // Entity-level overlap detects likely duplicates during merge.
        let duplicateCandidates = try duplicateConflictCandidates(payload: payload, viewContext: viewContext)
        for candidate in duplicateCandidates {
            conflicts.append(
                CloudSyncConflictResolver.Conflict(
                    localBackup: localInfo,
                    remoteBackup: incomingInfo,
                    conflictType: .duplicateEntity,
                    description: candidate
                )
            )
        }

        return conflicts
    }

    /// Extracts entity counts from backup payload
    func getPayloadEntityCounts(_ payload: BackupPayload) -> [String: Int] {
        return [
            "students": payload.students.count,
            "lessons": payload.lessons.count,
            "items": payload.items.count,
            "notes": payload.notes.count,
            "attendance": payload.attendance.count,
            "lessonAssignments": payload.lessonAssignments.count
        ]
    }

    func currentEntityCounts(viewContext: NSManagedObjectContext) throws -> [String: Int] {
        [
            "students": try viewContext.count(for: CDFetchRequest(CDStudent.self)),
            "lessons": try viewContext.count(for: CDFetchRequest(CDLesson.self)),
            "notes": try viewContext.count(for: CDFetchRequest(CDNote.self)),
            "attendance": try viewContext.count(for: CDFetchRequest(CDAttendanceRecord.self)),
            "lessonAssignments": try viewContext.count(for: CDFetchRequest(CDLessonAssignment.self))
        ]
    }

    func duplicateConflictCandidates(
        payload: BackupPayload,
        viewContext: NSManagedObjectContext
    ) throws -> [String] {
        var conflicts: [String] = []

        let localStudentIDs = Set(viewContext.safeFetch(CDFetchRequest(CDStudent.self)).compactMap(\.id))
        let localLessonIDs = Set(viewContext.safeFetch(CDFetchRequest(CDLesson.self)).compactMap(\.id))
        let localNoteIDs = Set(viewContext.safeFetch(CDFetchRequest(CDNote.self)).compactMap(\.id))
        let localAttendanceIDs = Set(viewContext.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).compactMap(\.id))
        let localAssignmentIDs = Set(viewContext.safeFetch(CDFetchRequest(CDLessonAssignment.self)).compactMap(\.id))

        appendDuplicateConflict(
            label: "students",
            incoming: Set(payload.students.map(\.id)),
            local: localStudentIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "lessons",
            incoming: Set(payload.lessons.map(\.id)),
            local: localLessonIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "notes",
            incoming: Set(payload.notes.map(\.id)),
            local: localNoteIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "attendance records",
            incoming: Set(payload.attendance.map(\.id)),
            local: localAttendanceIDs,
            to: &conflicts
        )
        appendDuplicateConflict(
            label: "lesson assignments",
            incoming: Set(payload.lessonAssignments.map(\.id)),
            local: localAssignmentIDs,
            to: &conflicts
        )

        return conflicts
    }

    func appendDuplicateConflict(
        label: String,
        incoming: Set<UUID>,
        local: Set<UUID>,
        to conflicts: inout [String]
    ) {
        guard !incoming.isEmpty, !local.isEmpty else { return }
        let overlap = incoming.intersection(local).count
        guard overlap > 0 else { return }
        conflicts.append("Potential duplicate \(label): \(overlap) incoming IDs already exist locally.")
    }

    func makeLocalBackupInfo(entityCounts: [String: Int]) -> CloudSyncConflictResolver.BackupInfo {
        CloudSyncConflictResolver.BackupInfo(
            url: URL(fileURLWithPath: "/local-database"),
            timestamp: Date(),
            entityCounts: entityCounts,
            checksum: "local",
            deviceID: "local",
            formatVersion: BackupFile.formatVersion
        )
    }

    func makeIncomingBackupInfo(entityCounts: [String: Int]) -> CloudSyncConflictResolver.BackupInfo {
        CloudSyncConflictResolver.BackupInfo(
            url: URL(fileURLWithPath: "/incoming-backup"),
            timestamp: Date(),
            entityCounts: entityCounts,
            checksum: "incoming",
            deviceID: "incoming",
            formatVersion: BackupFile.formatVersion
        )
    }
}
