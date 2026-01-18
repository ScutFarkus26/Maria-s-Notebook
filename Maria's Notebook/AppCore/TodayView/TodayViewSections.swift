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
                ContentUnavailableView("No reminders", systemImage: "bell.slash")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Overdue reminders (with visual indicator)
                if !viewModel.overdueReminders.isEmpty {
                    Text("Overdue")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                    ForEach(viewModel.overdueReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(viewModel.todaysReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(viewModel.anytimeReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
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
            Label("Reminders", systemImage: "bell.fill")
            Spacer()
            // Show sync status indicator
            if ReminderSyncService.shared.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .accessibilityLabel("Syncing reminders")
            } else if let error = ReminderSyncService.shared.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            } else if let lastSync = ReminderSyncService.shared.lastSuccessfulSync {
                Text(lastSync, style: .relative)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last synced \(lastSync, style: .relative) ago")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calendar Events Section

    var calendarEventsListSection: some View {
        Section {
            if viewModel.todaysCalendarEvents.isEmpty {
                ContentUnavailableView("No calendar events", systemImage: "calendar.badge.clock")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.todaysCalendarEvents, id: \.id) { event in
                    CalendarEventListRow(event: event)
                }
            }
        } header: {
            calendarEventsSectionHeader
        }
    }

    @ViewBuilder
    var calendarEventsSectionHeader: some View {
        HStack {
            Label("Calendar", systemImage: "calendar")
            Spacer()
            // Show sync status indicator
            if CalendarSyncService.shared.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .accessibilityLabel("Syncing calendar events")
            } else if let error = CalendarSyncService.shared.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Sync error: \(error)")
                    .accessibilityLabel("Sync error: \(error)")
            } else if let lastSync = CalendarSyncService.shared.lastSuccessfulSync {
                Text(lastSync, style: .relative)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last synced \(lastSync, style: .relative) ago")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Lessons Section

    var lessonsListSection: some View {
        Section {
            if viewModel.todaysLessons.isEmpty {
                ContentUnavailableView("No lessons scheduled today", systemImage: "calendar")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.todaysLessons, id: \.id) { sl in
                    LessonListRow(
                        lessonName: nameForLesson(sl.resolvedLessonID),
                        studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                        isPresented: sl.isPresented
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStudentLesson = sl
                    }
                }
            }
        } header: {
            Label("Lessons for Today", systemImage: "text.book.closed")
        }
    }

    // MARK: - Check-Ins Section

    var checkInsListSection: some View {
        Section {
            if viewModel.overdueSchedule.isEmpty && viewModel.todaysSchedule.isEmpty {
                ContentUnavailableView("No check-ins due", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !viewModel.overdueSchedule.isEmpty {
                    ForEach(viewModel.overdueSchedule) { item in
                        ContractScheduleListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                    }
                }
                if !viewModel.todaysSchedule.isEmpty {
                    ForEach(viewModel.todaysSchedule) { item in
                        ContractScheduleListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                    }
                }
            }
        } header: {
            Label("Scheduled Check-Ins", systemImage: "bell")
        }
    }

    // MARK: - Follow-Ups Section

    var inProgressListSection: some View {
        Section {
            if viewModel.staleFollowUps.isEmpty {
                ContentUnavailableView("No follow-ups due", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.staleFollowUps) { item in
                    ContractFollowUpListRow(item: item,
                                          studentName: resolveStudentName(for: item.work),
                                          lessonName: resolveLessonName(for: item.work),
                                          onTap: {
                        selectedWorkID = item.work.id
                    })
                }
            }
        } header: {
            Label("Follow-Ups Due", systemImage: "bolt")
        }
    }

    // MARK: - Completed Section

    var completedListSection: some View {
        Section {
            if viewModel.completedContracts.isEmpty {
                ContentUnavailableView("No completions yet", systemImage: "clock")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.completedContracts) { work in
                    CompletionListRow(
                        studentName: resolveStudentName(for: work),
                        lessonName: resolveLessonName(for: work),
                        work: work
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkID = work.id
                    }
                }
            }
        } header: {
            Label("Completed Today", systemImage: "checkmark.circle")
        }
    }

    // MARK: - Recent Observations Section

    var recentObservationsSection: some View {
        Section {
            if viewModel.recentNotes.isEmpty {
                ContentUnavailableView("No recent observations", systemImage: "note.text")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                        HStack(spacing: 10) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notePreview)
                                    .font(AppTheme.ScaledFont.bodySemibold)
                                    .foregroundStyle(.primary)
                                if !names.isEmpty {
                                    Text(names)
                                        .font(AppTheme.ScaledFont.captionSmall)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(note.createdAt, style: note.createdAt > Date().addingTimeInterval(-3600*24*3) ? .relative : .date)
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
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
        } header: {
            Label("Recent Observations", systemImage: "note.text")
        }
    }
}
