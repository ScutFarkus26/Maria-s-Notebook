// WorkCheckDayPicker.swift
// Picking the day a piece of work gets checked.
//
// The workspace knew two kinds of day. Today, from the button in the selection
// bar and the one item in the card's Schedule menu; and whichever four or five
// days the Scheduled strip below happened to be showing, by dragging a card
// onto one of them. Every other day — the Monday after next, the day before a
// break, the day the guide actually meant — meant paging the strip until that
// day was on screen and then aiming a drag at it.
//
// So this is a calendar. It hands back a start-of-day date and nothing else:
// the caller writes it the same way the button and the drop already do, so a
// day picked here and a day dropped onto cannot come to mean different things.

import SwiftUI

struct WorkCheckDayPicker: View {
    /// How many work items the chosen day will land on. Only the header reads
    /// it, and it is here for one reason: a bulk action that reads like a
    /// single one is the worst thing a picker like this can do.
    let count: Int
    let onPick: (Date) -> Void
    var onCancel: () -> Void = {}

    /// Opens on tomorrow. Today already has a button of its own a click away,
    /// so the first day this picker is *for* is the one after it.
    @State private var day: Date = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))

    /// Nothing earlier than today: a check scheduled into the past arrives
    /// already overdue, which is a state to fix, never one to choose.
    private var earliestDay: Date { AppCalendar.startOfDay(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headerTitle)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.top, AppTheme.Spacing.compact)

            DatePicker("", selection: $day, in: earliestDay..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)

            Divider()

            HStack(spacing: AppTheme.Spacing.small) {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button(confirmTitle) { onPick(AppCalendar.startOfDay(day)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppTheme.Spacing.compact)
        }
        .frame(minWidth: 300, maxWidth: 360)
    }

    private var headerTitle: String {
        count == 1 ? "Check this work on" : "Check \(count) work items on"
    }

    private var confirmTitle: String {
        "Check on \(DateFormatters.weekdayAndDate.string(from: day))"
    }
}

#Preview("One work item") {
    WorkCheckDayPicker(count: 1) { _ in }
}

#Preview("A selection") {
    WorkCheckDayPicker(count: 3) { _ in }
}
