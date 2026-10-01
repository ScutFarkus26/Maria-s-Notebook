import Foundation

// Leaving Early…: a pickup time set ahead on a child's record, which the
// guide and every assistant see on the tile and `EarlyPickupReminder` rings
// before. Setting one marks nothing. Back in Class brings a child who left
// early back into the room.

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

    /// Back in Class: a child who left early has come back, to present or
    /// late as they were, with the trip out on the record. Their pickup is
    /// done, so its reminder goes too.
    func markBack(_ row: Row) {
        guard AttendanceRules.allowsBack(for: row) else { return }
        let hadPickup = row.leavesAt != nil
        let saved = editRecord(for: row, failure: "Couldn't save that mark. Try again.") { store, record in
            store.markBack(record)
        }
        if saved, hadPickup { pickupEdits += 1 }
    }
}
