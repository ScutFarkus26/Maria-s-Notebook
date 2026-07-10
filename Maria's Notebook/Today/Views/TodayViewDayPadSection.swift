// TodayViewDayPadSection.swift
// Today's Pad — per-date plain text scratchpad. Collapsible section, auto-saved.

import SwiftUI

extension TodayView {

    var dayPadListSection: some View {
        Section {
            if isDayPadExpanded {
                DayPadEditor(day: viewModel.date)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            }
        } header: {
            dayPadSectionHeader
        }
    }

    @ViewBuilder
    var dayPadSectionHeader: some View {
        Button {
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                isDayPadExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Today's Pad")
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isDayPadExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
