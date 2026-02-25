// TodayViewSections.swift
// List sections for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - TodayView Sections Extension

extension TodayView {

    // MARK: - Todos Section (Things-inspired "Today" section)

    var todosListSection: some View {
        let selectedDay = AppCalendar.startOfDay(viewModel.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay

        return Section {
            if todayTodos.isEmpty {
                emptyStateText("No todos for today")
            } else {
                // Overdue todos (deadline before the selected day)
                let overdue = todayTodos.filter { todo in
                    guard let dueDate = todo.dueDate else { return false }
                    return dueDate < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay)
                }
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
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
                // Scheduled or due on selected day
                let dueOnDay = todayTodos.filter { todo in
                    let isOverdue = todo.dueDate.map { $0 < selectedDay && (todo.scheduledDate == nil || todo.scheduledDate! < nextDay) } ?? false
                    guard !isOverdue else { return false }
                    if let scheduled = todo.scheduledDate, scheduled >= selectedDay && scheduled < nextDay { return true }
                    if let dueDate = todo.dueDate, dueDate >= selectedDay && dueDate < nextDay { return true }
                    return false
                }
                if !dueOnDay.isEmpty {
                    if !overdue.isEmpty {
                        Text("Today")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
                    }
                    ForEach(dueOnDay) { todo in
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
                // High priority without a date on the selected day
                let overdueIDs = Set(overdue.map(\.id))
                let dueOnDayIDs = Set(dueOnDay.map(\.id))
                let highPriority = todayTodos.filter { todo in
                    !overdueIDs.contains(todo.id) && !dueOnDayIDs.contains(todo.id)
                }
                if !highPriority.isEmpty {
                    if !overdue.isEmpty || !dueOnDay.isEmpty {
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
            Button {
                isShowingNewTodo = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
    }

    /// Todos relevant to the selected day: scheduled for day, overdue deadline, due on date, or high priority.
    /// Someday todos are excluded.
    var todayTodos: [TodoItem] {
        let selectedDay = AppCalendar.startOfDay(viewModel.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay

        return todayTodoItems.filter { todo in
            guard !todo.isCompleted else { return false }
            // Exclude someday items
            guard !todo.isSomeday else { return false }

            // Scheduled for the selected date
            if let scheduled = todo.scheduledDate, scheduled >= selectedDay && scheduled < nextDay {
                return true
            }
            // Overdue deadline relative to the selected date
            if let dueDate = todo.dueDate, dueDate < selectedDay {
                // Only show overdue if not scheduled for a future date
                if let scheduled = todo.scheduledDate, scheduled >= nextDay {
                    return false
                }
                return true
            }
            // Deadline on the selected date (and not scheduled for a different day)
            if let dueDate = todo.dueDate, dueDate >= selectedDay && dueDate < nextDay {
                return true
            }
            // High priority (always shown)
            if todo.priority == .high {
                return true
            }
            return false
        }
        .sorted { lhs, rhs in
            let lhsOverdue = lhs.dueDate.map { $0 < selectedDay } ?? false
            let rhsOverdue = rhs.dueDate.map { $0 < selectedDay } ?? false
            let lhsScheduled = lhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let rhsScheduled = rhs.scheduledDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let lhsDueOnDay = lhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false
            let rhsDueOnDay = rhs.dueDate.map { $0 >= selectedDay && $0 < nextDay } ?? false

            // Overdue first, then scheduled for today, then due on selected day, then high priority
            if lhsOverdue != rhsOverdue { return lhsOverdue }
            if lhsScheduled != rhsScheduled { return lhsScheduled }
            if lhsDueOnDay != rhsDueOnDay { return lhsDueOnDay }
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
