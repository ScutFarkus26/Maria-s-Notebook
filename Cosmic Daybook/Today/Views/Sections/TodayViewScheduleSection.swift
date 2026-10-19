// TodayViewScheduleSection.swift
// Who is on the recurring schedules today, grouped by schedule, after the
// meetings. Hidden when no schedule has anyone on the day, and on a day
// school is closed. The rows are read in the view model's reload
// (`TodayScheduleSlots`); this only draws them.

import SwiftUI

extension TodayView {

    @ViewBuilder
    var scheduleListSection: some View {
        let slotCount = viewModel.scheduleGroups.reduce(0) { $0 + $1.slots.count }
        // The count first, so a day with nobody scheduled skips the school-day lookup.
        if slotCount > 0, TodaySectionVisibility.showsSchedule(
            slotCount: slotCount, isNonSchoolDay: isNonSchoolDaySync(viewModel.date)
        ) {
            Section {
                ForEach(viewModel.scheduleGroups) { group in
                    TodayScheduleGroupRow(group: group)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            } header: {
                sectionHeader("Schedule")
            }
        }
    }
}

// MARK: - Group Row

/// One schedule on Today: its name and icon, then each child on it today,
/// with the time the schedule gives and its note for that child.
struct TodayScheduleGroupRow: View {
    let group: TodayScheduleSlots.Group

    private var tint: Color { Color(hex: group.colorHex) ?? .accentColor }

    /// The time column, only when some slot has a time.
    private var showsTimes: Bool { group.slots.contains { $0.time != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(group.name)
                    .font(AppTheme.ScaledFont.callout.weight(.semibold))
            } icon: {
                Image.safeSymbol(group.icon)
                    .foregroundStyle(tint)
            }

            ForEach(group.slots) { slot in
                slotRow(slot)
            }
        }
        .padding(.vertical, 2)
    }

    private func slotRow(_ slot: TodayScheduleSlots.Slot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showsTimes {
                Text(slot.time ?? "")
                    .font(AppTheme.ScaledFont.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.studentName)
                    .font(AppTheme.ScaledFont.callout)
                if let notes = slot.notes {
                    Text(notes)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
