// DayHalfPicker.swift
// AM or PM for a scheduled lesson.
//
// Most scheduled presentations carry no time: they are planned as an order,
// and the hour and second in their date are bookkeeping, the ordering slot in
// their half (`DayHalfPlanner`). So this picker shows the half, and a start
// time the guide sets has its own control beside it (the sheet's Time row,
// `InboxStatusSection`), which stores it through the planner's rules. Choosing
// the other half here takes a set time off (`DayPeriod.applied`): 10:30 can't
// be an afternoon time.

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
