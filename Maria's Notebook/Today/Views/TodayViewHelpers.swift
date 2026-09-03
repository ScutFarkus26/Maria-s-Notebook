// TodayViewHelpers.swift
// Helper methods and actions for TodayView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

nonisolated private let logger = Logger.app_

// MARK: - TodayView Helpers Extension

extension TodayView {

    // MARK: - School Day Navigation
    // Thin wrappers over the shared school-day cache so the header and
    // day-rollover code read naturally.

    func isNonSchoolDaySync(_ date: Date) -> Bool {
        SchoolCalendarService.shared.isNonSchoolDaySync(date, using: viewContext)
    }

    func nextSchoolDaySync(after date: Date) -> Date {
        SchoolCalendarService.shared.nextSchoolDaySync(after: date, using: viewContext)
    }

    func previousSchoolDaySync(before date: Date) -> Date {
        SchoolCalendarService.shared.previousSchoolDaySync(before: date, using: viewContext)
    }

    func nearestSchoolDaySync(to date: Date) -> Date {
        SchoolCalendarService.shared.nearestSchoolDaySync(to: date, using: viewContext)
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
    func studentNames(for note: CDNote) -> String {
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

    /// Resolves student name from a CDWorkModel
    func resolveStudentName(for work: CDWorkModel) -> String {
        guard let uuid = UUID(uuidString: work.studentID) else { return "Student" }
        return displayNameForID(uuid)
    }

    /// Resolves display name from a CDWorkModel — prefers the work's own title, falls back to lesson name
    func resolveLessonName(for work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        guard let uuid = UUID(uuidString: work.lessonID) else { return "Lesson" }
        return nameForLesson(uuid)
    }

    // MARK: - Attendance Actions

    /// Marks a student as tardy for the current date
    func markTardy(_ studentID: UUID) {
        let store = CDAttendanceStore(context: viewContext, calendar: calendar)

        do {
            // ensureRecord fetches-or-creates the (student, day) record and
            // stamps attribution, the same path the attendance grid uses.
            guard let student = viewModel.studentsByID[studentID],
                  let record = try store.ensureRecord(for: student, on: viewModel.date) else { return }
            store.updateStatus(record, to: .tardy)
        } catch {
            logger.warning("Failed to load attendance record for tardy mark: \(error.localizedDescription)")
            return
        }

        // A failed save shows the "Couldn't Save" alert; the view model isn't
        // reloaded as though the change had persisted.
        guard saveCoordinator.save(viewContext, reason: "Mark tardy") else { return }
        viewModel.reload()
    }

    // MARK: - CDReminder Actions

    /// Toggles the completion status of a reminder
    func toggleReminder(_ reminder: CDReminder) {
        if reminder.isCompleted {
            reminder.markIncomplete()
        } else {
            reminder.markCompleted()
        }
        // A failed save shows the "Couldn't Save" alert; EventKit isn't told
        // about a completion change that didn't persist.
        guard saveCoordinator.save(viewContext, reason: "Update reminder") else { return }
        viewModel.reload()

        // Two-way sync: Update EventKit with the completion change
        Task<Void, Never> {
            do {
                try await ReminderSyncService.shared.updateReminderCompletionInEventKit(reminder)
            } catch {
                logger.warning("Failed to update reminder in EventKit: \(error)")
            }
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

        // Fetch filtered CDLessonAssignment IDs
        do {
            let fetchRequest: NSFetchRequest<CDLessonAssignment> =
                NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            fetchRequest.predicate = NSPredicate(
                format: "scheduledFor >= %@ AND scheduledFor < %@", dayStart as NSDate, dayEnd as NSDate
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)]
            let lessons = try viewContext.fetch(fetchRequest)
            filteredPresentationIDs = lessons.compactMap(\.id)
        } catch {
            filteredPresentationIDs = []
        }

        // Fetch filtered CDWorkCheckIn IDs (scheduled status only)
        // Uses CDWorkCheckIn for scheduled work check-ins
        do {
            let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
            let fetchRequest: NSFetchRequest<CDWorkCheckIn> =
                NSFetchRequest<CDWorkCheckIn>(entityName: "WorkCheckIn")
            fetchRequest.predicate = NSPredicate(
                format: "statusRaw == %@ AND date <= %@", scheduledStatus, dayEnd as NSDate
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCheckIn.id, ascending: true)]
            let checkIns = try viewContext.fetch(fetchRequest)
            filteredPlanItemIDs = checkIns.compactMap(\.id)
        } catch {
            filteredPlanItemIDs = []
        }
    }

    // MARK: - Todo Actions

    func toggleTodoItem(_ todo: CDTodoItem) {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            todo.isCompleted.toggle()
            if todo.isCompleted {
                todo.completedAt = Date()

                // Handle recurring todos — create the next occurrence
                if todo.recurrence != .none, let newTodo = makeRecurringTodo(from: todo) {
                    viewContext.insert(newTodo)
                }
            } else {
                todo.completedAt = nil
            }
            viewContext.safeSave()
        }
    }

    private func makeRecurringTodo(from todo: CDTodoItem) -> CDTodoItem? {
        let baseDate: Date
        let today = AppCalendar.startOfDay(Date())

        if todo.repeatAfterCompletion {
            baseDate = today
        } else {
            baseDate = todo.dueDate ?? today
        }

        let nextDueDate: Date?
        if todo.recurrence == .custom, todo.customIntervalDays > 0 {
            nextDueDate = calendar.date(byAdding: .day, value: Int(todo.customIntervalDays), to: baseDate)
        } else {
            nextDueDate = todo.recurrence.nextDate(after: baseDate)
        }

        guard let nextDueDate else { return nil }

        var nextScheduled: Date?
        if let scheduled = todo.scheduledDate, let due = todo.dueDate {
            let offset = calendar.dateComponents([.day], from: due, to: scheduled).day ?? 0
            nextScheduled = calendar.date(byAdding: .day, value: offset, to: nextDueDate)
        } else if todo.scheduledDate != nil {
            nextScheduled = nextDueDate
        }

        guard let context = todo.managedObjectContext else { return nil }
        let newTodo = CDTodoItem(context: context)
        newTodo.title = todo.title
        newTodo.notes = todo.notes
        newTodo.orderIndex = 0
        newTodo.studentIDs = todo.studentIDs
        newTodo.dueDate = nextDueDate
        newTodo.scheduledDate = nextScheduled
        newTodo.priority = todo.priority
        newTodo.recurrence = todo.recurrence
        newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
        newTodo.customIntervalDays = todo.customIntervalDays
        newTodo.tags = todo.tags
        return newTodo
    }
}
