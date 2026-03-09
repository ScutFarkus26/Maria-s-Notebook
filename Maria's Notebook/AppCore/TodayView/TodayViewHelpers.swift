// TodayViewHelpers.swift
// Helper methods and actions for TodayView - extracted for maintainability

import SwiftUI
import SwiftData
import OSLog

private let logger = Logger.app_

// MARK: - TodayView Helpers Extension

extension TodayView {

    // MARK: - School Day Navigation

    /// Synchronous helper that determines if a date is a non-school day using cached data.
    func isNonSchoolDaySync(_ date: Date) -> Bool {
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)
        return schoolDayCache.isNonSchoolDay(date)
    }

    /// Synchronous helper that returns the next school day strictly after the given date.
    func nextSchoolDaySync(after date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Synchronous helper that returns the previous school day strictly before the given date.
    func previousSchoolDaySync(before date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Synchronous helper that coerces the provided date to the nearest school day.
    func nearestSchoolDaySync(to date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)

        let day = AppCalendar.startOfDay(date)
        if !schoolDayCache.isNonSchoolDay(day) { return day }
        let prev = previousSchoolDaySync(before: day)
        let next = nextSchoolDaySync(after: day)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        if distPrev < distNext { return prev }
        // On tie or next closer, prefer next
        return next
    }

    // MARK: - Name Resolution

    /// Returns the lesson name for a given lesson ID
    func nameForLesson(_ id: UUID) -> String {
        viewModel.lessonName(for: id)
    }

    /// Returns the display name for a given student ID
    func displayNameForID(_ id: UUID) -> String {
        viewModel.displayName(for: id)
    }

    /// Returns a comma-separated string of student names for given IDs
    func studentNamesForIDs(_ ids: [UUID]) -> String {
        let names = ids.map { displayNameForID($0) }
        return names.joined(separator: ", ")
    }

    /// Returns student names for a note based on its scope
    func studentNames(for note: Note) -> String {
        switch note.scope {
        case .all: return ""
        case .student(let id):
            if viewModel.recentNoteStudentsByID[id] != nil { return displayNameForID(id) }
            return ""
        case .students(let ids):
            let names = ids.compactMap { sid in
                viewModel.recentNoteStudentsByID[sid].map { _ in displayNameForID(sid) }
            }
            return names.prefix(3).joined(separator: ", ")
        }
    }

    /// Resolves student name from a WorkModel
    func resolveStudentName(for work: WorkModel) -> String {
        guard let uuid = UUID(uuidString: work.studentID) else { return "Student" }
        return displayNameForID(uuid)
    }

    /// Resolves display name from a WorkModel — prefers the work's own title, falls back to lesson name
    func resolveLessonName(for work: WorkModel) -> String {
        let title = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        guard let uuid = UUID(uuidString: work.lessonID) else { return "Lesson" }
        return nameForLesson(uuid)
    }

    // MARK: - Attendance Actions

    /// Marks a student as tardy for the current date
    func markTardy(_ studentID: UUID) {
        let (day, _) = AppCalendar.dayRange(for: viewModel.date)
        let store = AttendanceStore(context: modelContext, calendar: calendar)

        do {
            var descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.studentID == studentID.uuidString && rec.date == day
                }
            )
            descriptor.fetchLimit = 1

            let records = try modelContext.fetch(descriptor)
            if let record = records.first {
                // Update existing record
                store.updateStatus(record, to: .tardy)
            } else {
                // Create new record if it doesn't exist
                guard viewModel.studentsByID[studentID] != nil else { return }
                let record = AttendanceRecord(studentID: studentID, date: day, status: .tardy)
                modelContext.insert(record)
            }

            // Save changes
            try modelContext.save()

            // Reload the view model to reflect changes
            viewModel.reload()
        } catch {
            // Error updating attendance status - continue silently
        }
    }

    /// Updates attendance status for a student
    func updateAttendanceStatus(for studentID: UUID, to status: AttendanceStatus) {
        let store = AttendanceStore(context: modelContext, calendar: calendar)
        let day = AppCalendar.startOfDay(viewModel.date)

        // Fetch or create the attendance record
        do {
            var descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.studentID == studentID.uuidString && rec.date == day
                }
            )
            descriptor.fetchLimit = 1

            let records = try modelContext.fetch(descriptor)
            if let record = records.first {
                // Update existing record
                store.updateStatus(record, to: status)
            } else {
                // Create new record if it doesn't exist
                // Verify student exists (should be in studentsByID cache)
                guard viewModel.studentsByID[studentID] != nil else {
                    return
                }
                let record = AttendanceRecord(studentID: studentID, date: day, status: status)
                modelContext.insert(record)
            }

            // Save changes
            try modelContext.save()

            // Reload the view model to reflect changes
            viewModel.reload()
        } catch {
            // Error updating attendance status - continue silently
        }
    }

    // MARK: - Reminder Actions

    /// Toggles the completion status of a reminder
    func toggleReminder(_ reminder: Reminder) {
        if reminder.isCompleted {
            reminder.markIncomplete()
        } else {
            reminder.markCompleted()
        }
        do {
            try modelContext.save()
            viewModel.reload()

            // Two-way sync: Update EventKit with the completion change
            Task {
                do {
                    try await ReminderSyncService.shared.updateReminderCompletionInEventKit(reminder)
                } catch {
                    logger.warning("Failed to update reminder in EventKit: \(error)")
                }
            }
        } catch {
            // Error toggling reminder - continue silently
        }
    }

    // MARK: - Toast

    /// Shows a toast message with animation
    func toast(_ message: String) {
        adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toastMessage = message
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.0))
            } catch {
                logger.warning("Failed to sleep for toast: \(error)")
            }
            adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }

    // MARK: - Filtered Queries

    /// Helper to update filtered queries when date or data changes
    func updateFilteredQueries() {
        let (dayStart, dayEnd) = AppCalendar.dayRange(for: viewModel.date)

        // Fetch filtered LessonAssignment IDs
        do {
            let lessonDescriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate<LessonAssignment> { lesson in
                    lesson.scheduledForDay >= dayStart && lesson.scheduledForDay < dayEnd
                },
                sortBy: [SortDescriptor(\LessonAssignment.id)]
            )
            let lessons = try modelContext.fetch(lessonDescriptor)
            filteredPresentationIDs = lessons.map { $0.id }
        } catch {
            filteredPresentationIDs = []
        }

        // Fetch filtered WorkCheckIn IDs (scheduled status only)
        // Uses WorkCheckIn for scheduled work check-ins
        do {
            let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
            let checkInDescriptor = FetchDescriptor<WorkCheckIn>(
                predicate: #Predicate<WorkCheckIn> { checkIn in
                    checkIn.statusRaw == scheduledStatus &&
                    checkIn.date <= dayEnd
                },
                sortBy: [SortDescriptor(\WorkCheckIn.id)]
            )
            let checkIns = try modelContext.fetch(checkInDescriptor)
            filteredPlanItemIDs = checkIns.map { $0.id }
        } catch {
            filteredPlanItemIDs = []
        }
    }

    // MARK: - Todo Actions

    func toggleTodoItem(_ todo: TodoItem) {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            todo.isCompleted.toggle()
            if todo.isCompleted {
                todo.completedAt = Date()

                // Handle recurring todos — create the next occurrence
                if todo.recurrence != .none {
                    let baseDate: Date
                    let today = AppCalendar.startOfDay(Date())

                    if todo.repeatAfterCompletion {
                        baseDate = today
                    } else {
                        baseDate = todo.dueDate ?? today
                    }

                    let nextDueDate: Date?
                    if todo.recurrence == .custom, let interval = todo.customIntervalDays {
                        nextDueDate = Calendar.current.date(byAdding: .day, value: interval, to: baseDate)
                    } else {
                        nextDueDate = todo.recurrence.nextDate(after: baseDate)
                    }

                    if let nextDueDate {
                        var nextScheduled: Date?
                        if let scheduled = todo.scheduledDate, let due = todo.dueDate {
                            let offset = Calendar.current.dateComponents([.day], from: due, to: scheduled).day ?? 0
                            nextScheduled = Calendar.current.date(byAdding: .day, value: offset, to: nextDueDate)
                        } else if todo.scheduledDate != nil {
                            nextScheduled = nextDueDate
                        }

                        let newTodo = TodoItem(
                            title: todo.title,
                            notes: todo.notes,
                            orderIndex: 0,
                            studentIDs: todo.studentIDs,
                            dueDate: nextDueDate,
                            scheduledDate: nextScheduled,
                            priority: todo.priority,
                            recurrence: todo.recurrence
                        )
                        newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
                        newTodo.customIntervalDays = todo.customIntervalDays
                        newTodo.tags = todo.tags
                        modelContext.insert(newTodo)
                    }
                }
            } else {
                todo.completedAt = nil
            }
            do {
                try modelContext.save()
            } catch {
                logger.warning("Failed to save todo: \(error)")
            }
        }
    }
}
