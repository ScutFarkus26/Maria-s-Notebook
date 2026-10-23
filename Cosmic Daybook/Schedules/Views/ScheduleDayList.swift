// ScheduleDayList.swift
// The Day view on iPhone: one list in time order, each row tagged with its
// lane's color and name (`ScheduleDayRows`), narrowed by the lane filter in
// the header.

import SwiftUI

struct ScheduleDayList: View {
    let day: ScheduleDay
    let style: ScheduleItemStyle
    let actions: ScheduleActions
    /// One lane only, or every lane.
    let laneFilter: UUID?
    let highlightedRowID: String?
    /// Set to a row's ID to scroll to it.
    let scrollTarget: String?

    private var rows: [ScheduleDayRows.Row] { ScheduleDayRows.rows(day, lane: laneFilter) }

    private var outLanes: [ScheduleDay.Lane] {
        day.lanes.filter { $0.isOut && (laneFilter == nil || laneFilter == $0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !day.isSchoolDay {
                    ContentUnavailableView(
                        "No school", systemImage: "sun.max",
                        description: Text("The school calendar has no school this day.")
                    )
                } else {
                    ForEach(outLanes) { lane in
                        outRow(lane)
                    }
                    ForEach(rows) { row in
                        rowView(row)
                            .id(row.id)
                    }
                    if rows.isEmpty, outLanes.isEmpty {
                        Text("Nothing on the schedule this day.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func rowView(_ row: ScheduleDayRows.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.lane.name)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(ScheduleLaneColor.color(of: row.lane))
                .lineLimit(1)
            ScheduleItemView(
                item: row.item, lane: row.lane, style: style, isHighlighted: highlightedRowID == row.id
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .scheduleBlockMenu(row.item.block, day: day.day, actions: actions)
    }

    private func outRow(_ lane: ScheduleDay.Lane) -> some View {
        HStack {
            Label(ScheduleText.outLine(lane.lane.name, isToday: style.isToday), systemImage: "person.badge.minus")
                .font(AppTheme.ScaledFont.callout)
                .foregroundStyle(.orange)
            Spacer()
            Button("Back In") { actions.setOut(lane.id, false, day.day) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .listRowSeparator(.hidden)
    }
}
