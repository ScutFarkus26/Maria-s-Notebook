// TodayViewModel+Reordering.swift
// Dragging rows on Today: the Lessons agenda and the Meetings section each keep
// their own order for the day (`TodayAgendaBuilder`).

import SwiftUI

extension TodayViewModel {

    /// Moves agenda items and persists the new order.
    func moveAgendaItem(from source: IndexSet, to destination: Int) {
        agendaItems.move(fromOffsets: source, toOffset: destination)
        TodayAgendaBuilder.saveOrder(items: agendaItems, day: date, context: context)
    }

    /// Moves scheduled meetings and persists the new order.
    func moveMeeting(from source: IndexSet, to destination: Int) {
        scheduledMeetings.move(fromOffsets: source, toOffset: destination)
        TodayAgendaBuilder.saveMeetingOrder(
            meetingIDs: scheduledMeetings.compactMap(\.id), day: date, context: context
        )
    }
}
