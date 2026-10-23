// SchedulesSubheader.swift
// The line under the Schedules title: "Monday, October 26 · 15 Cheshvan ·
// Vayera", the "1 change today" chip, and in the Day view the day's gentle
// warnings, each of which scrolls to the lesson it is about.

import SwiftUI

struct SchedulesSubheader: View {
    let model: SchedulesPageModel
    let onWarning: (ScheduleDay.Warning) -> Void

    private var title: String {
        guard model.mode == .week else { return HebrewDateText.headerLine(for: model.day) }
        let days = SchedulesPageModel.weekDays(containing: model.day, calendar: model.calendar)
        let first = days.first(where: { Weekday(date: $0, calendar: model.calendar) == .monday }) ?? model.day
        return ScheduleText.weekLine(monday: first)
    }

    private var chip: String? {
        switch model.mode {
        case .day:
            ScheduleText.changeChip(count: model.resolved.changeCount, isToday: model.isToday)
        case .week:
            ScheduleText.weekChangeChip(days: model.week.filter { $0.resolved.isChanged }.count)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(AppTheme.ScaledFont.callout)
            .foregroundStyle(model.isToday || model.mode == .week ? .primary : .secondary)
    }

    @ViewBuilder
    private var chipView: some View {
        if let chip {
            Text(chip)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14), in: Capsule())
                .fixedSize()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The chip beside the line when both fit, under it when they don't.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText.fixedSize()
                    chipView
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    chipView
                }
            }
            if model.mode == .day {
                ForEach(Array(model.warningLines.enumerated()), id: \.offset) { _, line in
                    Button {
                        onWarning(line.warning)
                    } label: {
                        Label(line.text, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the lesson")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
