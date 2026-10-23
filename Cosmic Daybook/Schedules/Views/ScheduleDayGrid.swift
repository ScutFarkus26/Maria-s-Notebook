// ScheduleDayGrid.swift
// The Day view on Mac and iPad: the lanes side by side under their headers,
// the time down the left, and a now line on today. Items sit at their time
// (`ScheduleGridLayout`); two that overlap share the lane's width.

import SwiftUI

struct ScheduleDayGrid: View {
    let day: ScheduleDay
    let style: ScheduleItemStyle
    let actions: ScheduleActions
    /// The item a warning was tapped for ("<lane id>/<item id>"), outlined for a moment.
    let highlightedRowID: String?
    @Binding var position: ScrollPosition

    static let timeColumnWidth: CGFloat = 52

    private var range: ClosedRange<Int> { ScheduleGridLayout.range(of: day) }

    /// Each lane's items, placed once per draw.
    private var placedByLane: [UUID: [ScheduleGridLayout.Placed]] {
        Dictionary(
            day.lanes.map { ($0.id, ScheduleGridLayout.place($0.items, from: range.lowerBound)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            laneHeaders
            Divider()
            if day.isSchoolDay {
                let placed = placedByLane
                let height = ScheduleGridLayout.contentHeight(range: range, placed: Array(placed.values))
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        timeAxis(height: height)
                        ForEach(day.lanes) { lane in
                            laneColumn(lane, placed: placed[lane.id] ?? [], height: height)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: height + 16)
                    .background(alignment: .topLeading) { hourLines }
                    .overlay(alignment: .topLeading) { nowLine }
                    .padding(.vertical, 8)
                }
                .scrollPosition($position)
            } else {
                ContentUnavailableView(
                    "No school", systemImage: "sun.max",
                    description: Text("The school calendar has no school this day.")
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Headers

    private var laneHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.timeColumnWidth, height: 1)
            ForEach(day.lanes) { lane in
                ScheduleLaneHeader(lane: lane, day: day.day, style: style, actions: actions)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Time

    private var hours: [Int] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: 60))
    }

    private func timeAxis(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(hours, id: \.self) { minute in
                Text(TimetableDay.clockText(minute))
                    .font(AppTheme.ScaledFont.captionSmall.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                    .offset(y: ScheduleGridLayout.top(of: minute, from: range.lowerBound) - 7)
            }
        }
        .frame(width: Self.timeColumnWidth, height: height, alignment: .topTrailing)
    }

    private var hourLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { minute in
                Rectangle()
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                    .frame(height: 0.5)
                    .padding(.leading, Self.timeColumnWidth)
                    .offset(y: ScheduleGridLayout.top(of: minute, from: range.lowerBound))
            }
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        if style.isToday {
            TimelineView(.everyMinute) { context in
                let minute = TimetableDay.minute(of: context.date)
                if range.contains(minute) {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .padding(.leading, Self.timeColumnWidth - 4)
                        Rectangle()
                            .fill(.red)
                            .frame(height: 1.5)
                    }
                    .offset(y: ScheduleGridLayout.top(of: minute, from: range.lowerBound) - 4)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Now, \(TimetableDay.clockText(minute))")
                }
            }
        }
    }

    // MARK: - Lanes

    private func laneColumn(
        _ lane: ScheduleDay.Lane, placed items: [ScheduleGridLayout.Placed], height: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(items) { placed in
                    let columnWidth = width / CGFloat(placed.columns)
                    ScheduleItemView(
                        item: placed.item, lane: lane.lane, style: style,
                        isHighlighted: highlightedRowID == "\(lane.id.uuidString)/\(placed.item.id)",
                        isCompact: placed.height < ScheduleGridLayout.compactBlockHeight
                    )
                    .frame(width: max(columnWidth - 6, 20), height: placed.height, alignment: .topLeading)
                    .clipped()
                    .scheduleBlockMenu(placed.item.block, day: day.day, actions: actions)
                    .offset(x: CGFloat(placed.column) * columnWidth + 3, y: placed.top)
                }
                if lane.isOut {
                    Text(ScheduleText.outLine(lane.lane.name, isToday: style.isToday))
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(width: width)
                }
            }
        }
        .frame(height: height)
    }
}

/// A lane's name over its column, with its menu: Add to This Day…, and Out
/// Today or Back In on a person's lane.
struct ScheduleLaneHeader: View {
    let lane: ScheduleDay.Lane
    let day: Date
    let style: ScheduleItemStyle
    let actions: ScheduleActions

    private var canAddBlocks: Bool { !(lane.lane.kind == .person && lane.lane.isGuide) }

    var body: some View {
        Menu {
            if canAddBlocks {
                Button("Add to This Day…", systemImage: "plus") { actions.addToDay(lane.id, day) }
            }
            if lane.lane.kind == .person {
                if lane.isOut {
                    Button("Back In", systemImage: "person.badge.plus") { actions.setOut(lane.id, false, day) }
                } else {
                    Button("Out Today", systemImage: "person.badge.minus") { actions.setOut(lane.id, true, day) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(ScheduleLaneColor.color(of: lane.lane))
                    .frame(width: 9, height: 9)
                Text(lane.lane.name)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if lane.isOut {
                    Text("Out")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHint("Shows what you can change in this lane")
    }
}
