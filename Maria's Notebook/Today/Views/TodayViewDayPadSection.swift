// TodayViewDayPadSection.swift
// Today's Pad — per-date plain text scratchpad. Collapsible section, auto-saved.
//
// The pad is empty on almost every day in the live notebook, so the section
// only appears when the day's pad has something written on it, or when the
// guide has deliberately opened it. An empty, closed pad stays reachable from
// the toolbar `+` menu ("Today's Pad"), which opens it.

import SwiftUI
import CoreData

extension TodayView {

    var dayPadListSection: some View {
        DayPadSectionView(day: viewModel.date, isExpanded: $isDayPadExpanded)
    }
}

/// Standalone so the day's pad row can be fetched here rather than adding a
/// property to `TodayViewModel` — the same shape `DeadlinesSectionView` uses.
struct DayPadSectionView: View {
    let day: Date
    @Binding var isExpanded: Bool

    @FetchRequest private var pads: FetchedResults<CDDayPad>

    init(day: Date, isExpanded: Binding<Bool>) {
        self.day = day
        _isExpanded = isExpanded
        _pads = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "day == %@", AppCalendar.startOfDay(day) as NSDate)
        )
    }

    /// Whitespace alone is not writing: a pad the guide opened, typed a
    /// newline into and abandoned should not pin the section open forever.
    private var hasBody: Bool {
        pads.contains { !($0.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        if TodaySectionVisibility.showsDayPad(hasBody: hasBody, isExpanded: isExpanded) {
            Section {
                if isExpanded {
                    DayPadEditor(day: day)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                }
            } header: {
                header
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        Button {
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                isExpanded.toggle()
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
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
