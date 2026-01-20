// TodayViewSections.swift
// List sections for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - TodayView Sections Extension

extension TodayView {

    // MARK: - Reminders Section

    var remindersListSection: some View {
        Section {
            if viewModel.overdueReminders.isEmpty && viewModel.todaysReminders.isEmpty && viewModel.anytimeReminders.isEmpty {
                emptyStateText("No reminders")
            } else {
                // Overdue reminders (with visual indicator)
                if !viewModel.overdueReminders.isEmpty {
                    Text("Overdue")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    ForEach(viewModel.overdueReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
                }
                // Today's reminders
                if !viewModel.todaysReminders.isEmpty {
                    if !viewModel.overdueReminders.isEmpty {
                        Text("Due Today")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(viewModel.todaysReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
                }
                // Anytime reminders (no due date)
                if !viewModel.anytimeReminders.isEmpty {
                    if !viewModel.overdueReminders.isEmpty || !viewModel.todaysReminders.isEmpty {
                        Text("Anytime")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(viewModel.anytimeReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
                }
            }
        } header: {
            remindersSectionHeader
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
                    .foregroundStyle(.orange.opacity(0.7))
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calendar Events Section

    var calendarEventsListSection: some View {
        Section {
            if viewModel.todaysCalendarEvents.isEmpty {
                emptyStateText("No events")
            } else {
                ForEach(viewModel.todaysCalendarEvents, id: \.id) { event in
                    CalendarEventListRow(event: event)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
        } header: {
            calendarEventsSectionHeader
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
                    .foregroundStyle(.orange.opacity(0.7))
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Lessons Section

    var lessonsListSection: some View {
        Section {
            if viewModel.todaysLessons.isEmpty {
                emptyStateText("No lessons scheduled")
            } else {
                ForEach(viewModel.todaysLessons, id: \.id) { sl in
                    LessonListRow(
                        lessonName: nameForLesson(sl.resolvedLessonID),
                        studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                        isPresented: sl.isPresented
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStudentLesson = sl
                    }
                }
            }
        } header: {
            sectionHeader("Lessons")
        }
    }

    // MARK: - Needs Attention Section (Check-Ins + Follow-Ups)

    var checkInsListSection: some View {
        let hasCheckIns = !viewModel.overdueSchedule.isEmpty || !viewModel.todaysSchedule.isEmpty
        let hasFollowUps = !viewModel.staleFollowUps.isEmpty

        return Section {
            if !hasCheckIns && !hasFollowUps {
                emptyStateText("Nothing needs attention")
            } else {
                // Check-ins subsection
                if hasCheckIns {
                    if hasFollowUps {
                        Text("Check-Ins")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(viewModel.overdueSchedule) { item in
                        ScheduledWorkListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                    ForEach(viewModel.todaysSchedule) { item in
                        ScheduledWorkListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                }

                // Follow-ups subsection
                if hasFollowUps {
                    if hasCheckIns {
                        Text("Follow-Ups")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(viewModel.staleFollowUps) { item in
                        FollowUpWorkListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                }
            }
        } header: {
            sectionHeader("Needs Attention")
        }
    }

    // Keep for backwards compatibility but return EmptyView since consolidated
    var inProgressListSection: some View {
        EmptyView()
    }

    // MARK: - Completed Section

    var completedListSection: some View {
        Section {
            if viewModel.completedWork.isEmpty {
                emptyStateText("No completions yet")
            } else {
                ForEach(viewModel.completedWork) { work in
                    CompletionListRow(
                        studentName: resolveStudentName(for: work),
                        lessonName: resolveLessonName(for: work),
                        work: work
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkID = work.id
                    }
                }
            }
        } header: {
            sectionHeader("Completed")
        }
    }

    // MARK: - Recent Observations Section

    var recentObservationsSection: some View {
        Section {
            if !isObservationsCollapsed {
                if viewModel.recentNotes.isEmpty {
                    emptyStateText("No recent observations")
                } else {
                    ForEach(viewModel.recentNotes, id: \.id) { note in
                        let notePreview = note.body.split(separator: "\n").first.map(String.init) ?? ""
                        let names = studentNames(for: note)
                        let accessibilityLabel: String = {
                            var label = "Observation: \(notePreview)"
                            if !names.isEmpty {
                                label += ", for \(names)"
                            }
                            return label
                        }()

                        Button {
                            switch note.scope {
                            case .student(let id):
                                appRouter.requestOpenStudentDetail(id)
                            case .all, .students:
                                break
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(notePreview)
                                    .font(AppTheme.ScaledFont.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    if !names.isEmpty {
                                        Text(names)
                                            .font(AppTheme.ScaledFont.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text(note.createdAt, style: note.createdAt > Date().addingTimeInterval(-3600*24*3) ? .relative : .date)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .accessibilityLabel(accessibilityLabel)
                        .accessibilityHint("Double tap to view student details. Swipe left to edit.")
#if os(iOS)
                        .swipeActions(edge: .trailing) {
                            Button {
                                noteBeingEdited = note
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
#endif
                        .contextMenu {
                            Button {
                                noteBeingEdited = note
                            } label: {
                                Label("Edit Note", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
        } header: {
            collapsibleSectionHeader("Recent Observations", isCollapsed: $isObservationsCollapsed, count: viewModel.recentNotes.count)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    @ViewBuilder
    private func collapsibleSectionHeader(_ title: String, isCollapsed: Binding<Bool>, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if isCollapsed.wrappedValue && count > 0 {
                    Text("(\(count))")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed.wrappedValue ? 0 : 90))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.ScaledFont.callout)
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}
