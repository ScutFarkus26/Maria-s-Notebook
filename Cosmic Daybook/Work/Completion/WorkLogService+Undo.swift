// WorkLogService+Undo.swift
// The receipt a logged work check hands back, and how it is reversed.
//
// Snapshots are keyed by `NSManagedObjectID`, the same choice
// `ImmediatePresentationRecordingService.UndoToken` makes, so an Undo tapped
// after a sync merge still restores exactly the rows this call touched.

import CoreData
import Foundation

extension WorkLogService {

    struct RowSnapshot {
        let objectID: NSManagedObjectID
        let statusRaw: String
        let completedAt: Date?
        let lastTouchedAt: Date?

        init(_ work: CDWorkModel) {
            objectID = work.objectID
            statusRaw = work.statusRaw
            completedAt = work.completedAt
            lastTouchedAt = work.lastTouchedAt
        }

        func restore(_ work: CDWorkModel) {
            work.statusRaw = statusRaw
            work.completedAt = completedAt
            work.lastTouchedAt = lastTouchedAt
        }
    }

    struct ParticipantSnapshot {
        let objectID: NSManagedObjectID
        let completedAt: Date?

        init(_ participant: CDWorkParticipantEntity) {
            objectID = participant.objectID
            completedAt = participant.completedAt
        }
    }

    struct CheckInSnapshot {
        let objectID: NSManagedObjectID
        let statusRaw: String
        let date: Date?

        init(_ checkIn: CDWorkCheckIn) {
            objectID = checkIn.objectID
            statusRaw = checkIn.statusRaw
            date = checkIn.date
        }
    }

    /// Everything one `log` call changed, in the order it was changed.
    struct UndoToken {
        let day: Date
        var rows: [RowSnapshot] = []
        var participants: [ParticipantSnapshot] = []
        var checkIns: [CheckInSnapshot] = []
        /// Completion records, notes and their student links made by the call.
        var createdObjectIDs: [NSManagedObjectID] = []

        init(day: Date) {
            self.day = day
        }
    }

    // MARK: - Undo

    /// Puts every touched row, participant and check-in back and deletes what
    /// the call created, then saves.
    static func undo(
        _ token: UndoToken,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) throws {
        guard token.rows.contains(where: { context.existing($0.objectID) != nil }) else {
            throw LogError.undoUnavailable
        }
        revert(token, in: context)
        let saved = saveCoordinator?.save(context, reason: "Undo work check") ?? context.safeSave()
        guard saved else {
            throw LogError.saveFailed(saveCoordinator?.lastSaveErrorMessage ?? "The undo could not be saved.")
        }
    }

    /// The in-memory half of `undo`; also what a failed save falls back to.
    static func revert(_ token: UndoToken, in context: NSManagedObjectContext) {
        // Snapshots were appended as rows were touched; the first snapshot of
        // an object is its pre-log state, so restore in reverse order.
        for snapshot in token.rows.reversed() {
            if let work = context.existing(CDWorkModel.self, snapshot.objectID) {
                snapshot.restore(work)
            }
        }
        for snapshot in token.participants.reversed() {
            if let participant = context.existing(CDWorkParticipantEntity.self, snapshot.objectID) {
                participant.completedAt = snapshot.completedAt
            }
        }
        for snapshot in token.checkIns.reversed() {
            if let checkIn = context.existing(CDWorkCheckIn.self, snapshot.objectID) {
                checkIn.statusRaw = snapshot.statusRaw
                checkIn.date = snapshot.date
            }
        }
        for objectID in token.createdObjectIDs {
            if let object = context.existing(objectID), !object.isDeleted {
                context.delete(object)
            }
        }
        context.processPendingChanges()
    }
}
