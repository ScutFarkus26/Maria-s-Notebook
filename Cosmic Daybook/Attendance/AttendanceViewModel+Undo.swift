import Foundation
import CoreData
import OSLog

// The roll's undoable changes: the bulk marks (Mark N Present, Close
// Arrival's absences) and one child's mark at a time, for ⌘Z.

// MARK: - Bulk marks

extension AttendanceViewModel {
    /// What a sweeping mark changed, for its Undo: the records it marked
    /// (every one of them unmarked before), each as the mark left it.
    struct BulkMark {
        let day: Date
        let records: [AttendanceRecordSnapshot]
    }

    /// Marks everyone still unmarked present; anyone already marked keeps
    /// their mark. Not ahead of the day. Returns what the Undo needs, or nil
    /// when nobody changed.
    func markUnmarkedPresent(modelContext: NSManagedObjectContext) -> BulkMark? {
        guard !isFuture else { return nil }
        do {
            let marked = try CDAttendanceStore(context: modelContext)
                .markUnmarkedPresent(for: selectedDate, students: students)
            guard !marked.isEmpty else { return nil }
            try modelContext.obtainPermanentIDs(for: marked.filter(\.objectID.isTemporaryID))
            changed(marked)
            return BulkMark(day: selectedDate, records: marked.map(AttendanceRecordSnapshot.init))
        } catch {
            report("Couldn't mark the rest present. Try again.", error, while: "marking the rest present")
            return nil
        }
    }

    /// Takes back a bulk mark: its children still exactly as it left them go
    /// back to unmarked. A child changed since keeps the change: marked
    /// differently, given a reason ("Absent, Sick" after Close Arrival), or
    /// out and Back in Class after Mark N Present. Matching the status alone
    /// used to unmark those too, and lose the reason or the trip.
    /// Returns how many.
    @discardableResult
    func undoBulkMark(_ undo: BulkMark, modelContext: NSManagedObjectContext) -> Int {
        let store = CDAttendanceStore(context: modelContext)
        var reverted: [CDAttendanceRecord] = []
        for marked in undo.records {
            guard let record = try? modelContext.existingObject(with: marked.objectID) as? CDAttendanceRecord,
                  !record.isDeleted, marked.matches(record),
                  store.updateStatus(record, to: .unmarked) else { continue }
            reverted.append(record)
        }
        if undo.day == selectedDate { updateRows(for: reverted) }
        return reverted.count
    }
}

// MARK: - One child's mark, undoably

extension AttendanceViewModel {
    /// One child's change, for ⌘Z: the record as it was and as the change
    /// left it. Undoing it hands back its own opposite, which is the redo.
    struct MarkUndo {
        let day: Date
        let before: AttendanceRecordSnapshot
        let after: AttendanceRecordSnapshot
    }

    /// Runs `change` on `row` and returns what puts it back, or nil when
    /// nothing changed.
    func recordingUndo(
        for row: AttendanceRow,
        modelContext: NSManagedObjectContext,
        _ change: (AttendanceRow) -> Void
    ) -> MarkUndo? {
        let key = row.student.cloudKitKey
        let before = recordsByStudentID[key].map(AttendanceRecordSnapshot.init)
        change(row)
        guard let record = recordsByStudentID[key] else { return nil }
        if record.objectID.isTemporaryID {
            // Gone at the next save: the undo needs the id that lasts.
            try? modelContext.obtainPermanentIDs(for: [record])
        }
        let after = AttendanceRecordSnapshot(record)
        let start = before ?? AttendanceRecordSnapshot(blank: record.objectID)
        guard !start.matches(record) else { return nil }
        return MarkUndo(day: selectedDate, before: start, after: after)
    }

    /// Puts the child back as `undo` found them, unless they've been marked
    /// again since. Returns the redo, or nil when nothing changed.
    func undoMark(_ undo: MarkUndo, modelContext: NSManagedObjectContext) -> MarkUndo? {
        guard let record = try? modelContext.existingObject(with: undo.after.objectID) as? CDAttendanceRecord,
              CDAttendanceStore(context: modelContext).revert(record, to: undo.before, ifStill: undo.after)
        else { return nil }
        if undo.day == selectedDate { updateRows(for: [record]) }
        return MarkUndo(day: undo.day, before: undo.after, after: AttendanceRecordSnapshot(record))
    }
}
