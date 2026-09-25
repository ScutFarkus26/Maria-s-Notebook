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
                try await dependencies.reminderSync.updateReminderCompletionInEventKit(reminder)
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
        Task {
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

    // MARK: - Todo Actions

    /// Completes or reopens a todo in place. Completion — the next occurrence
    /// of a repeating todo included — is `TodoCompletionService`'s rule.
    func toggleTodoItem(_ todo: CDTodoItem) {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            if todo.isCompleted {
                TodoCompletionService.reopen(todo)
            } else {
                TodoCompletionService.complete(todo, calendar: calendar)
            }
            saveCoordinator.save(viewContext, reason: "Toggle todo")
        }
    }
}
