import Foundation
import CoreData

/// Copies EventKit's events onto the rows that mirror them, `CDCalendarEvent`,
/// writing only what changed. (Reminders sync was retired 2026-11-03.)
///
/// A sync used to reassign every field of every row EventKit returned and
/// stamp `lastSyncedAt = Date()` on each, so every sync saved every row it
/// saw: one CloudKit export per row, the same again imported on the other
/// device, and a history transaction that kept the backup change gate open
/// all day. Danny decided (2026-09-25) that `lastSyncedAt` is stamped only
/// on a row that is new or changed. Every other value is copied exactly as
/// before, but assigned only when it differs from what the row holds, so a
/// sync over unchanged EventKit data leaves the context without changes and
/// `safeSave()` writes nothing. Dates count as different only when they are
/// a millisecond or more apart (Danny, 2026-09-25; see `isSameInstant`).
enum EventKitMirror {

    /// What one pass did to the stored rows.
    nonisolated struct Outcome: Equatable, Sendable {
        var inserted = 0
        var updated = 0
        var deleted = 0
    }

    // MARK: - Comparison

    /// Whether a stored date already holds `incoming`, to the millisecond
    /// (Danny, 2026-09-25). CloudKit keeps dates in milliseconds, so a row
    /// another device wrote comes back with EventKit's sub-millisecond digits
    /// cut off; comparing exactly would rewrite (and re-upload) it on every
    /// sync, and with both devices syncing one list they would rewrite each
    /// other's rows indefinitely. Dates less than a millisecond apart count as
    /// the same, and the stored value is left as it is.
    static func isSameInstant(_ stored: Date?, _ incoming: Date?) -> Bool {
        switch (stored, incoming) {
        case (nil, nil):
            return true
        case let (stored?, incoming?):
            return abs(stored.timeIntervalSince(incoming)) < 0.001
        default:
            return false
        }
    }

    /// Whether a stored text field already holds `incoming`, code unit for
    /// code unit. Swift's `==` calls canonically equivalent strings equal (a
    /// precomposed "é" and "e" plus a combining accent), but the row stores
    /// the exact form EventKit returned, which is what the old copy wrote.
    static func isSameText(_ stored: String?, _ incoming: String?) -> Bool {
        switch (stored, incoming) {
        case (nil, nil):
            return true
        case let (stored?, incoming?):
            return stored.utf16.elementsEqual(incoming.utf16)
        default:
            return false
        }
    }
}
