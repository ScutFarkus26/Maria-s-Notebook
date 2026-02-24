// TodayViewSections.swift
// List sections for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - TodayView Sections Extension

extension TodayView {

    // MARK: - Todos Section (Things-inspired "Today" section)

    var todosListSection: some View {
        Section {
            if todayTodos.isEmpty {
                emptyStateText("No todos for today")
            } else {
                // Overdue todos
                let overdue = todayTodos.filter { $0.isOverdue }
                if !overdue.isEmpty {
                    Text("Overdue")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    ForEach(overdue) { todo in
                        TodoTodayRow(todo: todo, onToggle: { toggleTodoItem(todo) }, onTap: { selectedTodoItem = todo })
                            .id(todo.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleTodoItem(todo)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    selectedTodoItem = todo
                                } label: {
                                    Label("View", systemImage: "eye")
                                }
                                .tint(.blue)
                            }
                    }
                }
                // Due today
                let dueToday = todayTodos.filter { $0.isDueToday && !$0.isOverdue }
                if !dueToday.isEmpty {
                    if !overdue.isEmpty {
                        Text("Due Today")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(dueToday) { todo in
                        TodoTodayRow(todo: todo, onToggle: { toggleTodoItem(todo) }, onTap: { selectedTodoItem = todo })
                            .id(todo.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleTodoItem(todo)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
                // High priority without due date
                let highPriority = todayTodos.filter { !$0.isOverdue && !$0.isDueToday }
                if !highPriority.isEmpty {
                    if !overdue.isEmpty || !dueToday.isEmpty {
                        Text("High Priority")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(highPriority) { todo in
                        TodoTodayRow(todo: todo, onToggle: { toggleTodoItem(todo) }, onTap: { selectedTodoItem = todo })
                            .id(todo.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleTodoItem(todo)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        } header: {
            todosSectionHeader
        }
    }

    @ViewBuilder
    var todosSectionHeader: some View {
        HStack {
            Text("Todos")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = todayTodos.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Todos relevant to Today: overdue + due today + high priority
    var todayTodos: [TodoItem] {
        todayTodoItems.filter { todo in
            !todo.isCompleted && (todo.isOverdue || todo.isDueToday || todo.priority == .high)
        }
        .sorted { lhs, rhs in
            // Overdue first, then due today, then high priority
            if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
            if lhs.isDueToday != rhs.isDueToday { return lhs.isDueToday }
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
    }

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
                        .id(event.id)
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

    // MARK: - Presented Lessons Section

    var presentedLessonsListSection: some View {
        Section {
            let presented = viewModel.todaysLessons.filter { $0.isPresented }
            if presented.isEmpty {
                emptyStateText("No lessons presented yet")
            } else {
                ForEach(presented) { sl in
                    LessonListRow(
                        lessonName: nameForLesson(sl.resolvedLessonID),
                        studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                        isPresented: true
                    )
                    .id(sl.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStudentLesson = sl
                    }
                }
            }
        } header: {
            presentedLessonsSectionHeader
        }
    }

    @ViewBuilder
    var presentedLessonsSectionHeader: some View {
        HStack {
            Text("Lessons Presented")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.todaysLessons.filter { $0.isPresented }.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Checked Work Section

    var checkedWorkListSection: some View {
        Section {
            if viewModel.completedWork.isEmpty {
                emptyStateText("No work checked yet")
            } else {
                ForEach(viewModel.completedWork) { work in
                    CompletionListRow(
                        studentName: resolveStudentName(for: work),
                        lessonName: resolveLessonName(for: work),
                        work: work
                    )
                    .id(work.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkID = work.id
                    }
                }
            }
        } header: {
            checkedWorkSectionHeader
        }
    }

    @ViewBuilder
    var checkedWorkSectionHeader: some View {
        HStack {
            Text("Work Checked")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            let count = viewModel.completedWork.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Unified Agenda Section

    var agendaListSection: some View {
        Section {
            if viewModel.agendaItems.isEmpty {
                emptyStateText("No lessons or work items scheduled")
            } else {
                ForEach(viewModel.agendaItems) { item in
                    agendaRow(for: item)
                        .id(item.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .onMove { source, destination in
                    viewModel.moveAgendaItem(from: source, to: destination)
                }
            }
        } header: {
            sectionHeader("Agenda")
        }
    }

    @ViewBuilder
    private func agendaRow(for item: AgendaItem) -> some View {
        HStack(spacing: 10) {
            agendaTypeIndicator(for: item)
            agendaRowContent(for: item)
        }
    }

    @ViewBuilder
    private func agendaTypeIndicator(for item: AgendaItem) -> some View {
        let (icon, color): (String, Color) = {
            switch item {
            case .lesson:
                return ("book.fill", .blue)
            case .scheduledWork:
                return ("clock.fill", .orange)
            case .followUp:
                return ("arrow.uturn.left.circle.fill", .purple)
            case .groupedScheduledWork:
                return ("person.3.fill", .orange)
            case .groupedFollowUp:
                return ("person.3.fill", .purple)
            }
        }()

        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(color.opacity(0.8))
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func agendaRowContent(for item: AgendaItem) -> some View {
        switch item {
        case .lesson(let sl):
            LessonListRow(
                lessonName: nameForLesson(sl.resolvedLessonID),
                studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                isPresented: sl.isPresented
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedStudentLesson = sl
            }

        case .scheduledWork(let scheduled):
            ScheduledWorkListRow(
                item: scheduled,
                studentName: resolveStudentName(for: scheduled.work),
                lessonName: resolveLessonName(for: scheduled.work),
                onTap: {
                    selectedWorkID = scheduled.work.id
                }
            )

        case .followUp(let followUp):
            FollowUpWorkListRow(
                item: followUp,
                studentName: resolveStudentName(for: followUp.work),
                lessonName: resolveLessonName(for: followUp.work),
                onTap: {
                    selectedWorkID = followUp.work.id
                }
            )

        case .groupedScheduledWork(let items):
            GroupedScheduledWorkListRow(
                items: items,
                studentNames: items.map { resolveStudentName(for: $0.work) },
                lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
                isFlexible: items.first?.work.checkInStyle == .flexible,
                onTap: { workID in
                    selectedWorkID = workID
                }
            )

        case .groupedFollowUp(let items):
            GroupedFollowUpWorkListRow(
                items: items,
                studentNames: items.map { resolveStudentName(for: $0.work) },
                lessonName: items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson",
                isFlexible: items.first?.work.checkInStyle == .flexible,
                onTap: { workID in
                    selectedWorkID = workID
                }
            )
        }
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
                    .id(work.id)
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
