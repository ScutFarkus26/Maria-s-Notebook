import CoreData
import Foundation

/// A `WorkLogService` receipt kept with a child's meeting draft, so a status
/// a work card set can be taken back after the app has quit: by Clear, by
/// Rest, or by choosing another outcome on the card (bug hunt 2026-10-09, #9
/// and #10). Logging Working again would leave the close's skipped check-ins,
/// completed todos and completion record behind; the receipt restores them.
///
/// Object IDs are kept as URIs and the snapshots as plain values. It also
/// keeps how the meeting left the work, because `WorkLogService.undo` only
/// checks that the rows still exist and would overwrite a change made after
/// the meeting.
nonisolated struct MeetingCloseToken: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        var objectURI: URL
        var statusRaw: String
        var completionOutcomeRaw: String?
        var completedAt: Date?
        var lastTouchedAt: Date?
    }

    struct Participant: Codable, Equatable, Sendable {
        var objectURI: URL
        var completedAt: Date?
    }

    struct CheckIn: Codable, Equatable, Sendable {
        var objectURI: URL
        var statusRaw: String
        var date: Date?
    }

    var day: Date
    var rows: [Row] = []
    var participants: [Participant] = []
    var checkIns: [CheckIn] = []
    var completedTodoURIs: [URL] = []
    var createdObjectURIs: [URL] = []
    /// The work's status as the meeting left it.
    var leftStatusRaw: String
    /// The work's last-touched time as the meeting left it; anything that
    /// logs or reviews the work afterwards moves it.
    var leftLastTouchedAt: Date?

    /// What happened when a card's earlier changes were asked back.
    enum TakeBack: Equatable {
        /// The meeting hadn't changed the work's status.
        case nothing
        case takenBack
        /// The work was changed after the meeting, so it was left alone.
        case changedSince
        /// A receipt no longer names rows on this device (an older draft, or
        /// a store reset); the caller falls back to logging Working.
        case unreadable
    }

    /// Both nil, or within a millisecond (a draft's dates go through JSON).
    static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 0.001
        default: false
        }
    }

    /// Whether every receipt can be taken back, newest first: each one must
    /// find the work as it left it, and taking it back leaves the work as the
    /// next older one left it.
    static func canTakeBack(_ tokens: [MeetingCloseToken], from work: CDWorkModel) -> Bool {
        let uri = work.objectID.uriRepresentation()
        var statusRaw = work.statusRaw
        var touched = work.lastTouchedAt
        for token in tokens.reversed() {
            guard statusRaw == token.leftStatusRaw,
                  sameInstant(touched, token.leftLastTouchedAt),
                  let row = token.rows.first(where: { $0.objectURI == uri }) else { return false }
            statusRaw = WorkStatusMigration.merged(statusRaw: row.statusRaw, outcomeRaw: row.completionOutcomeRaw)
            touched = row.lastTouchedAt
        }
        return true
    }
}

// MARK: - Receipts in and out

extension MeetingCloseToken {
    /// The receipt of a decision card's log, once the card has finished with
    /// `work`. Nil when an object it names can't be given a lasting ID.
    init?(_ token: WorkLogService.UndoToken, leaving work: CDWorkModel, in context: NSManagedObjectContext) {
        func uri(_ objectID: NSManagedObjectID) -> URL? {
            guard objectID.isTemporaryID else { return objectID.uriRepresentation() }
            // Something the log touched was inserted but not yet saved: its
            // ID changes on the save, so take the lasting one now.
            guard let object = context.registeredObject(for: objectID),
                  (try? context.obtainPermanentIDs(for: [object])) != nil,
                  !object.objectID.isTemporaryID else { return nil }
            return object.objectID.uriRepresentation()
        }

        var rows: [Row] = []
        for snapshot in token.rows {
            guard let objectURI = uri(snapshot.objectID) else { return nil }
            rows.append(Row(
                objectURI: objectURI, statusRaw: snapshot.statusRaw,
                completionOutcomeRaw: snapshot.completionOutcomeRaw,
                completedAt: snapshot.completedAt, lastTouchedAt: snapshot.lastTouchedAt
            ))
        }
        var participants: [Participant] = []
        for snapshot in token.participants {
            guard let objectURI = uri(snapshot.objectID) else { return nil }
            participants.append(Participant(objectURI: objectURI, completedAt: snapshot.completedAt))
        }
        var checkIns: [CheckIn] = []
        for snapshot in token.checkIns {
            guard let objectURI = uri(snapshot.objectID) else { return nil }
            checkIns.append(CheckIn(objectURI: objectURI, statusRaw: snapshot.statusRaw, date: snapshot.date))
        }
        let todos = token.completedTodos.compactMap(uri)
        let created = token.createdObjectIDs.compactMap(uri)
        guard todos.count == token.completedTodos.count, created.count == token.createdObjectIDs.count else {
            return nil
        }
        self.init(
            day: token.day, rows: rows, participants: participants, checkIns: checkIns,
            completedTodoURIs: todos, createdObjectURIs: created,
            leftStatusRaw: work.statusRaw, leftLastTouchedAt: work.lastTouchedAt
        )
    }

    /// The receipt `WorkLogService` reverses, or nil when a URI no longer
    /// names a store on this device.
    func undoToken(in context: NSManagedObjectContext) -> WorkLogService.UndoToken? {
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        func objectID(_ uri: URL) -> NSManagedObjectID? {
            coordinator.managedObjectID(forURIRepresentation: uri)
        }
        var token = WorkLogService.UndoToken(day: day)
        for row in rows {
            guard let id = objectID(row.objectURI) else { return nil }
            token.rows.append(WorkLogService.RowSnapshot(
                objectID: id, statusRaw: row.statusRaw, completionOutcomeRaw: row.completionOutcomeRaw,
                completedAt: row.completedAt, lastTouchedAt: row.lastTouchedAt
            ))
        }
        for participant in participants {
            guard let id = objectID(participant.objectURI) else { return nil }
            token.participants.append(
                WorkLogService.ParticipantSnapshot(objectID: id, completedAt: participant.completedAt)
            )
        }
        for checkIn in checkIns {
            guard let id = objectID(checkIn.objectURI) else { return nil }
            token.checkIns.append(WorkLogService.CheckInSnapshot(
                objectID: id, statusRaw: checkIn.statusRaw, date: checkIn.date
            ))
        }
        let todos = completedTodoURIs.compactMap(objectID)
        let created = createdObjectURIs.compactMap(objectID)
        guard todos.count == completedTodoURIs.count, created.count == createdObjectURIs.count else { return nil }
        token.completedTodos = todos
        token.createdObjectIDs = created
        return token
    }

    /// Puts `work` back as it was before this meeting's changes, newest
    /// first, through `WorkLogService`. In memory only: the caller saves.
    /// Changes nothing unless every receipt can be taken back.
    static func takeBack(
        _ tokens: [MeetingCloseToken], of work: CDWorkModel, in context: NSManagedObjectContext
    ) -> TakeBack {
        guard !tokens.isEmpty else { return .nothing }
        let receipts = tokens.compactMap { $0.undoToken(in: context) }
        guard receipts.count == tokens.count else { return .unreadable }
        guard canTakeBack(tokens, from: work) else { return .changedSince }
        for receipt in receipts.reversed() {
            WorkLogService.revert(receipt, in: context)
        }
        return .takenBack
    }
}

// MARK: - Snapshots from stored values

// The snapshots only take a live object; a stored receipt has plain values.

private extension WorkLogService.RowSnapshot {
    init(
        objectID: NSManagedObjectID, statusRaw: String, completionOutcomeRaw: String?,
        completedAt: Date?, lastTouchedAt: Date?
    ) {
        self.objectID = objectID
        self.statusRaw = statusRaw
        self.completionOutcomeRaw = completionOutcomeRaw
        self.completedAt = completedAt
        self.lastTouchedAt = lastTouchedAt
    }
}

private extension WorkLogService.ParticipantSnapshot {
    init(objectID: NSManagedObjectID, completedAt: Date?) {
        self.objectID = objectID
        self.completedAt = completedAt
    }
}

private extension WorkLogService.CheckInSnapshot {
    init(objectID: NSManagedObjectID, statusRaw: String, date: Date?) {
        self.objectID = objectID
        self.statusRaw = statusRaw
        self.date = date
    }
}
