import Foundation

// Leaving Early…: a pickup time set ahead on a child's record, which the
// guide and every assistant see on the tile and `EarlyPickupReminder` rings
// before. Setting one marks nothing.

extension AssistantAttendanceViewModel {

    /// Whether the menu offers Leaving Early… for `row` on the day on screen.
    func allowsPickup(for row: Row) -> Bool {
        canMark && AttendanceRules.allowsPickup(for: row, on: date)
    }

    /// Sets when the child is due to be picked up early, or with nil removes
    /// it, creating the record if there is none yet.
    func setPickup(_ time: Date?, for row: Row) {
        let saved = editRecord(for: row, failure: "Couldn't save that pickup time. Try again.") { store, record in
            store.updateLeavesAt(record, to: time)
        }
        if saved { pickupEdits += 1 }
    }
}
