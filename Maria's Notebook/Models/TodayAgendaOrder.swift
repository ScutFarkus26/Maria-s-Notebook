// TodayAgendaOrder.swift
// Persists the user's custom ordering of agenda items for a given day.

import Foundation
import SwiftData

/// Stores a single positional entry in the user's daily agenda ordering.
/// Each day's agenda is represented by a set of entries, one per item, sorted by `position`.
@Model final class TodayAgendaOrder: Identifiable {
    #Index<TodayAgendaOrder>([\.day])

    var id: UUID = UUID()

    /// The day this ordering applies to (start of day, normalized).
    var day: Date = Date.distantPast

    /// The type of item ("lesson", "scheduledWork", "followUp").
    var itemTypeRaw: String = ""

    /// The ID of the referenced item (StudentLesson.id, WorkCheckIn.id, or WorkModel.id).
    var itemID: UUID = UUID()

    /// The position in the agenda (0-based).
    var position: Int = 0

    var itemType: AgendaItemType {
        get { AgendaItemType(rawValue: itemTypeRaw) ?? .lesson }
        set { itemTypeRaw = newValue.rawValue }
    }

    init(day: Date, itemType: AgendaItemType, itemID: UUID, position: Int) {
        self.id = UUID()
        self.day = AppCalendar.startOfDay(day)
        self.itemTypeRaw = itemType.rawValue
        self.itemID = itemID
        self.position = position
    }
}
