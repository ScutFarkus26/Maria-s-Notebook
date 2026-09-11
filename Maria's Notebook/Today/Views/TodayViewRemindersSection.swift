// TodayViewRemindersSection.swift
// Reminders and Calendar sections for TodayView - extracted for maintainability
//
// Both sections gate themselves through `TodaySectionVisibility`: an empty
// feed renders nothing rather than a header over the words "No reminders".
// The undated ("Anytime") reminders — forty-one of them in the live notebook,
// almost all last year's — sit behind a disclosure that remembers whether the
// guide opened it, so they stay reachable without owning the fold.

import SwiftUI
import CoreData

// MARK: - TodayView Reminders & Calendar Section Extension

extension TodayView {

    // MARK: - Reminders Section

    @ViewBuilder
    var remindersListSection: some View {
        if TodaySectionVisibility.showsReminders(
            overdue: viewModel.overdueReminders.count,
            dueToday: viewModel.todaysReminders.count,
            anytime: viewModel.anytimeReminders.count
        ) {
            Section {
                overdueRemindersRows
                todaysRemindersRows
                anytimeRemindersRows
            } header: {
                remindersSectionHeader
            }
        }
    }

    /// Overdue reminders, flagged red and always on the fold.
    @ViewBuilder
    private var overdueRemindersRows: some View {
        if !viewModel.overdueReminders.isEmpty {
            Text("Overdue")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.red.opacity(UIConstants.OpacityConstants.heavy))
                .textCase(.uppercase)
                .tracking(0.5)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
            ForEach(viewModel.overdueReminders, id: \.objectID) { reminder in
                reminderRow(reminder)
            }
        }
    }

    /// Reminders due on the selected day — the subheader only appears when
    /// there is an overdue group above it to be told apart from.
    @ViewBuilder
    private var todaysRemindersRows: some View {
        if !viewModel.todaysReminders.isEmpty {
            if !viewModel.overdueReminders.isEmpty {
                reminderSubheader("Due Today")
            }
            ForEach(viewModel.todaysReminders, id: \.objectID) { reminder in
                reminderRow(reminder)
            }
        }
    }

    /// Undated reminders, behind a collapsed disclosure that remembers its state.
    @ViewBuilder
    private var anytimeRemindersRows: some View {
        if TodaySectionVisibility.showsAnytimeDisclosure(anytime: viewModel.anytimeReminders.count) {
            anytimeRemindersHeader
            if isAnytimeRemindersExpanded {
                ForEach(viewModel.anytimeReminders, id: \.objectID) { reminder in
                    reminderRow(reminder)
                }
            }
        }
    }

    @ViewBuilder
    private var anytimeRemindersHeader: some View {
        Button {
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                isAnytimeRemindersExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Anytime · \(viewModel.anytimeReminders.count)")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isAnytimeRemindersExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anytime reminders, \(viewModel.anytimeReminders.count)")
        .accessibilityHint(isAnytimeRemindersExpanded ? "Collapses the list" : "Expands the list")
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
    }

    @ViewBuilder
    private func reminderSubheader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
    }

    @ViewBuilder
    private func reminderRow(_ reminder: CDReminder) -> some View {
        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
            .id(reminder.id)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .swipeActions(edge: .leading) {
                Button {
                    toggleReminder(reminder)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
    }

    @ViewBuilder
    var remindersSectionHeader: some View {
        HStack {
            Text("Reminders")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            // Show sync status indicator
            if ReminderSyncService.shared.isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                    .accessibilityLabel("Syncing reminders")
            } else if let error = ReminderSyncService.shared.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(UIConstants.OpacityConstants.prominent))
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            }
        }
        .accessibilityElement(children: .combine)
    }

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
            // Show sync status indicator
            if CalendarSyncService.shared.isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                    .accessibilityLabel("Syncing calendar events")
            } else if let error = CalendarSyncService.shared.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(UIConstants.OpacityConstants.prominent))
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
