// TodayViewCalendarSection.swift
// The Calendar section for TodayView: today's Apple Calendar events.
//
// It gates itself through `TodaySectionVisibility`: an empty feed renders
// nothing rather than a header over an empty list. (Until 2026-11-03 it
// shared a file with the Reminders section, retired with Reminders sync.)

import SwiftUI
import CoreData

// MARK: - TodayView Calendar Section Extension

extension TodayView {

    // MARK: - Calendar Events Section

    @ViewBuilder
    var calendarEventsListSection: some View {
        if TodaySectionVisibility.showsCalendarEvents(count: viewModel.todaysCalendarEvents.count) {
            Section {
                ForEach(viewModel.todaysCalendarEvents, id: \.id) { event in
                    CalendarEventListRow(event: event)
                        .id(event.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            } header: {
                calendarEventsSectionHeader
            }
        }
    }

    @ViewBuilder
    var calendarEventsSectionHeader: some View {
        HStack {
            Text("Calendar")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            // Show sync status indicator; the Sample Class never syncs, so
            // the real service's spinner and warning don't belong there.
            if dependencies.isSampleClassroom {
                EmptyView()
            } else if dependencies.calendarSync.isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                    .accessibilityLabel("Syncing calendar events")
            } else if let error = dependencies.calendarSync.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(UIConstants.OpacityConstants.prominent))
                    .help("Calendar didn't sync. \(error)")
                    .accessibilityLabel("Calendar didn't sync. \(error)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
