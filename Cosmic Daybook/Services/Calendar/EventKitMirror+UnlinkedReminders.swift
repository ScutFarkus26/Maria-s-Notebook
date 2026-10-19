import Foundation
import CoreData

// MARK: - Unlinked reminder rows
//
// A reminder row with no Apple Reminders link (`eventKitReminderID` nil) is a
// copy a restore brought back: backups leave the links out on purpose
// (`ReminderDTO`), and before the 2026-10-05 data model fixes a restore wrote
// the backup's reminder rows back without them (a restore now leaves reminder
// rows alone, `BackupEntityRegistry.keptOnRestoreEntityNames`, but those
// copies are still in iCloud, and a device on an older build can still make
// them). A sync with no row for a reminder inserted a linked one beside the
// copy, a double (Simplify the app, Phase 9). It now takes the copy over
// instead: same title and due date; the copy keeps its id and the notes
// attached to it, and gets this device's link.
//
// Links stay per device, as they always have been: `calendarItemIdentifier`
// and the list's `calendarIdentifier` differ on every device, so each device
// syncing a list keeps its own rows and Today shows only this device's list.
// Matching rows across devices by EventKit's external identifier was tried
// in the 2026-10-17 bug hunt (#13) and backed out; nothing here does that.
// Two devices that take over the same copy at once each set their own link,
// iCloud keeps the last one, and the other device gets a row of its own on
// its next sync (it takes another copy, or inserts one).

extension EventKitMirror {

    /// Whether a stored due date is the one EventKit gives, to the second:
    /// a backup writes dates in whole seconds (ISO 8601), so a restored copy
    /// of a 9:00:00.4 due date reads 9:00:00. A reminder with no due date
    /// matches only a row with none.
    static func isSameDueDate(_ stored: Date?, _ incoming: Date?) -> Bool {
        switch (stored, incoming) {
        case (nil, nil):
            return true
        case let (stored?, incoming?):
            return abs(stored.timeIntervalSince(incoming)) < 1
        default:
            return false
        }
    }
}

/// The rows of one sync with no Apple Reminders link, filed by title, for
/// reminders the sync has no row for. Each row is taken at most once.
struct UnlinkedReminderPool {
    /// By `folded()` title, as `NotebookJunkCleanup.duplicateReminders` groups
    /// copies: case, accents and surrounding spaces don't count.
    private var byTitle: [String: [CDReminder]]

    init(_ rows: [CDReminder]) {
        byTitle = Dictionary(grouping: rows.filter { $0.eventKitReminderID == nil }) { $0.title.folded() }
    }

    /// The unlinked copy of `data` a sync should take over, if any, taken out
    /// of the pool so no other reminder gets it. A copy has the same title and
    /// due date (`isSameDueDate`); open or done doesn't have to match, since
    /// the reminder may have been ticked since the backup and the sync copies
    /// EventKit's state onto the row anyway.
    ///
    /// Of several copies, the first by `precedes`: every device ranks them the
    /// same way, and the copies a sync leaves are the ones
    /// `NotebookJunkCleanup.duplicateReminders` clears once a linked copy exists.
    mutating func takeCopy(of data: ReminderSyncData) -> CDReminder? {
        guard !byTitle.isEmpty else { return nil }
        let title = data.title.folded()
        guard let rows = byTitle[title] else { return nil }
        let due = data.dueDateComponents?.date
        let copies = rows.filter {
            EventKitMirror.isSameDueDate($0.dueDate, due)
                && Self.isSameCreation($0.createdAt, data.creationDate, hasDueDate: due != nil)
        }
        guard let taken = copies.min(by: { Self.precedes($0, $1, for: data) }) else { return nil }
        byTitle[title]?.removeAll { $0 === taken }
        return taken
    }

    /// Whether a row was made when the reminder was: `insertReminder` stores
    /// `createdAt = creationDate` and backups keep it, so a restored copy
    /// matches to the second, and a new reminder of the same title does not
    /// (it must not take over last year's row, whose notes would go when the
    /// new reminder is cleared). With either date missing, only a reminder
    /// with a due date can match on title and due date alone.
    static func isSameCreation(_ stored: Date?, _ incoming: Date?, hasDueDate: Bool) -> Bool {
        guard let stored, let incoming else { return hasDueDate }
        return abs(stored.timeIntervalSince(incoming)) < 1
    }

    /// Which of two copies of `data` to take first: one open or done as the
    /// reminder is, then one with notes attached (so they stay with a linked
    /// row), then the older, then the lower id. The id is the same on every
    /// device, unlike the object ID.
    static func precedes(_ lhs: CDReminder, _ rhs: CDReminder, for data: ReminderSyncData) -> Bool {
        let lhsState = lhs.isCompleted == data.isCompleted
        let rhsState = rhs.isCompleted == data.isCompleted
        if lhsState != rhsState { return lhsState }
        let lhsNotes = (lhs.noteItems?.count ?? 0) > 0
        let rhsNotes = (rhs.noteItems?.count ?? 0) > 0
        if lhsNotes != rhsNotes { return lhsNotes }
        let lhsCreated = lhs.createdAt ?? .distantFuture
        let rhsCreated = rhs.createdAt ?? .distantFuture
        if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
        return (lhs.id?.uuidString ?? "~") < (rhs.id?.uuidString ?? "~")
    }
}
