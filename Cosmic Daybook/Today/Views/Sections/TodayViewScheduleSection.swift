// TodayViewScheduleSection.swift
// The day on the Schedules timetable, after the meetings: the rooms' blocks,
// the guide's turns ("Your turn in the adolescent room 10:30–11:45") and the
// other people's blocks, in time order, with changes for the day marked.
// The guide's lessons aren't here: the agenda lists them. Hidden on a day
// with nothing on the timetable, and on a day school is closed. The rows are
// read in the view model's reload (`TodayScheduleRows`); this only draws them.

import SwiftUI

extension TodayView {

    @ViewBuilder
    var scheduleListSection: some View {
        let rowCount = viewModel.scheduleRows.count
        // The count first, so a day with nothing on it skips the school-day lookup.
        if rowCount > 0, TodaySectionVisibility.showsSchedule(
            rowCount: rowCount, isNonSchoolDay: isNonSchoolDaySync(viewModel.date)
        ) {
            Section {
                ForEach(viewModel.scheduleRows) { row in
                    TodayScheduleRow(row: row)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                }
            } header: {
                sectionHeader("Schedule")
            }
        }
    }
}

// MARK: - Row

/// One block on Today: its time, its title, and who or where, tagged with
/// its lane's color; "Today only" or "Changed today" when it is.
struct TodayScheduleRow: View {
    let row: TodayScheduleRows.Row

    private var tint: Color { ScheduleLaneColor.color(of: row.lane) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.time ?? "")
                .font(AppTheme.ScaledFont.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                    Text(row.title)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(row.mark == .out ? .orange : .primary)
                    if let mark = markText {
                        Text(mark)
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.orange)
                    }
                }
                if let detail = row.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var markText: String? {
        switch row.mark {
        case .todayOnly: "Today only"
        case .changed: "Changed today"
        case .out, nil: nil
        }
    }
}
