// StudentsViewComponents.swift
// Reusable components extracted from StudentsView

import SwiftUI
import CoreData

// MARK: - Empty State Views

/// Reusable empty state for when no students are present
struct NoStudentsEmptyState: View {
    let onAddStudent: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No students yet", systemImage: "person.3")
        } description: {
            Text("Click the plus button to add your first student.")
        } actions: {
            Button {
                onAddStudent()
            } label: {
                Label("Add Student", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Reusable empty state for when no student is selected
struct SelectStudentEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("Select a Student", systemImage: "person.circle")
        } description: {
            Text("Choose a student from the list to view their details.")
        }
    }
}

/// Shown when the "Here" filter is active but no attendance has been taken today.
struct NoAttendanceEmptyState: View {
    let onShowAll: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No One Marked Present", systemImage: "checkmark.circle")
        } description: {
            Text("Take attendance to see who's here today.")
        } actions: {
            Button("Show All Students") {
                onShowAll()
            }
        }
    }
}

// MARK: - Add Student Menu

/// Add-student menu with the CSV import surfaced as a visible menu item
/// (instead of hiding it behind a context menu on the plus button).
struct AddStudentMenu: View {
    let onAddStudent: () -> Void
    let onImportCSV: () -> Void
    var onRollover: (() -> Void)?

    var body: some View {
        Menu {
            Button {
                onAddStudent()
            } label: {
                Label("New Student", systemImage: "person.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button {
                onImportCSV()
            } label: {
                Label("Import Students from CSV…", systemImage: "arrow.down.doc")
            }

            if let onRollover {
                Divider()

                Button {
                    onRollover()
                } label: {
                    Label("School Year Rollover…", systemImage: "calendar.badge.clock")
                }
            }
        } label: {
            Label("Add Student", systemImage: "plus")
        }
    }
}
