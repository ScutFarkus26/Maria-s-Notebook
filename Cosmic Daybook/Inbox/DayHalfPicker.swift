// DayHalfPicker.swift
// AM or PM for a scheduled moment that carries no time.
//
// A scheduled presentation is planned as an order, not a timetable, so the hour
// and minute in its date are bookkeeping — the ordering offset within its half.
// Showing them in a date picker invited the guide to set a time the calendar
// then quietly overwrote on the next drag. This picker shows the one part of
// that date the guide actually chose.

import SwiftUI

struct DayHalfPicker: View {
    /// Nil while nothing is scheduled, which is when the control hides itself:
    /// there is no half to pick until there is a day to pick it on.
    @Binding var date: Date?

    @Environment(\.calendar) private var calendar

    private var half: Binding<DayPeriod> {
        Binding(
            get: { date.map { DayPeriod(scheduledFor: $0, using: calendar) } ?? .morning },
            set: { newValue in
                guard let current = date else { return }
                date = newValue.applied(to: current, using: calendar)
            }
        )
    }

    var body: some View {
        if date != nil {
            Picker("Half of Day", selection: half) {
                ForEach(DayPeriod.allCases, id: \.self) { period in
                    Text(period.abbreviation).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Two segments of two characters each; left to itself the control
            // would stretch across the whole sheet.
            .fixedSize()
            .accessibilityLabel("Half of day")
        }
    }
}
