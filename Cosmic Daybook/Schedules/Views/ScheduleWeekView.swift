// ScheduleWeekView.swift
// The Week view: one lane at a time (the header's lane picker), over the
// week's school days. Mac and iPad show the days as columns; iPhone, a list
// by day. A changed day is marked, and each day's menu has Copy Day To…,
// Add to This Day… and Show This Day.

import SwiftUI

struct ScheduleWeekView: View {
    let columns: [SchedulesPageModel.WeekColumn]
    let lane: TimetableLaneSnapshot
    let lanesByID: [UUID: TimetableLaneSnapshot]
    let names: [String: String]
    let isToday: (Date) -> Bool
    let isCompact: Bool
    let actions: ScheduleActions
    let onCopyDay: (Weekday) -> Void
    let onShowDay: (Date) -> Void

    private var canEditBlocks: Bool { !(lane.kind == .person && lane.isGuide) }

    private func style(for day: Date) -> ScheduleItemStyle {
        ScheduleItemStyle(lanesByID: lanesByID, names: names, isToday: isToday(day))
    }

    private func items(_ column: SchedulesPageModel.WeekColumn) -> [ScheduleDay.Item] {
        column.resolved.lane(lane.id)?.items ?? []
    }

    var body: some View {
        if isCompact {
            list
        } else {
            grid
        }
    }

    // MARK: - Mac and iPad

    private var grid: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(columns) { column in
                    VStack(alignment: .leading, spacing: 6) {
                        dayHeader(column)
                        Divider()
                        dayItems(column)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(
                        isToday(column.day) ? Color.accentColor.opacity(UIConstants.OpacityConstants.trace) : .clear,
                        in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - iPhone

    private var list: some View {
        List {
            ForEach(columns) { column in
                Section {
                    dayItems(column)
                } header: {
                    dayHeader(column)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - A day

    /// "Monday, Oct 26" over a list; "Mon 26" over a narrow column, with
    /// the Changed mark under it there.
    private func dayHeader(_ column: SchedulesPageModel.WeekColumn) -> some View {
        let date = isCompact
            ? column.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            : column.day.formatted(.dateTime.weekday(.abbreviated).day())
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(date)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(isToday(column.day) ? Color.accentColor : .primary)
                    .lineLimit(1)
                if isCompact { changedMark(column) }
                Spacer(minLength: 0)
                dayMenu(column)
            }
            if !isCompact { changedMark(column) }
        }
    }

    @ViewBuilder
    private func changedMark(_ column: SchedulesPageModel.WeekColumn) -> some View {
        if column.resolved.isChanged {
            Label("Changed", systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.orange)
                .imageScale(.small)
                .lineLimit(1)
        }
    }

    private func dayMenu(_ column: SchedulesPageModel.WeekColumn) -> some View {
        let weekday = Weekday(date: column.day)
        return Menu {
            Button("Show This Day", systemImage: "calendar") { onShowDay(column.day) }
            if canEditBlocks {
                Button("Add to This Day…", systemImage: "plus") { actions.addToDay(lane.id, column.day) }
                Button("Copy \(weekday.rawValue) To…", systemImage: "doc.on.doc") { onCopyDay(weekday) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("\(weekday.rawValue) options")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
    }

    @ViewBuilder
    private func dayItems(_ column: SchedulesPageModel.WeekColumn) -> some View {
        let style = style(for: column.day)
        if !column.resolved.isSchoolDay {
            Text("No school")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        } else if column.resolved.lane(lane.id)?.isOut == true {
            Text(ScheduleText.outLine(lane.name, isToday: style.isToday))
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.orange)
        } else if items(column).isEmpty {
            Text("Nothing this day")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items(column)) { item in
                ScheduleItemView(item: item, lane: lane, style: style)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
                    .scheduleBlockMenu(item.block, day: column.day, actions: actions)
            }
        }
    }
}

/// Copy Day To…: which other school days get a copy of the day's blocks.
struct ScheduleCopyDaySheet: View {
    let source: Weekday
    let laneName: String
    let onCopy: ([Weekday]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targets: Set<Weekday> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Weekday.schoolDays.filter { $0 != source }) { weekday in
                        Toggle(weekday.rawValue, isOn: Binding(
                            get: { targets.contains(weekday) },
                            set: { isOn in
                                if isOn { targets.insert(weekday) } else { targets.remove(weekday) }
                            }
                        ))
                    }
                } footer: {
                    Text("\(laneName)’s \(source.rawValue) blocks are added to each day you pick. "
                        + "A block already there at the same time isn’t added twice.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Copy \(source.rawValue) To")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        onCopy(Weekday.schoolDays.filter(targets.contains))
                        dismiss()
                    }
                    .disabled(targets.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
