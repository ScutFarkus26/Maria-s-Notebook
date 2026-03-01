// StudentsViewComponents.swift
// Reusable components extracted from StudentsView

import SwiftUI

// MARK: - Empty State View

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

// MARK: - Select Student Empty State

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

// MARK: - Sort and Filter Controls

/// Compact sort and filter controls for sidebar/toolbar
struct SortFilterControls: View {
    @Binding var sortOrderRaw: String
    @Binding var filterRaw: String
    let effectiveSortOrder: SortOrder
    let selectedFilter: StudentsFilter
    let showEditButton: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Sort Order Menu
            sortMenu

            // Filter Menu
            filterMenu

            Spacer()

            // Edit button (iOS only, manual sort mode)
            #if os(iOS)
            if showEditButton {
                EditButton()
                    .controlSize(.small)
            }
            #endif
        }
    }

    private var sortMenu: some View {
        Menu {
            Button {
                adaptiveWithAnimation { sortOrderRaw = "alphabetical" }
            } label: {
                Label("A–Z", systemImage: "textformat.abc")
                if effectiveSortOrder == .alphabetical {
                    Image(systemName: "checkmark")
                }
            }
            Button {
                adaptiveWithAnimation { sortOrderRaw = "manual" }
            } label: {
                Label("Manual", systemImage: "arrow.up.arrow.down")
                if effectiveSortOrder == .manual {
                    Image(systemName: "checkmark")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort")
            }
            .font(AppTheme.ScaledFont.captionSemibold)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                adaptiveWithAnimation { filterRaw = "all" }
            } label: {
                Label("All", systemImage: "person.3.fill")
                if selectedFilter == .all {
                    Image(systemName: "checkmark")
                }
            }
            Button {
                adaptiveWithAnimation { filterRaw = "presentNow" }
            } label: {
                Label("Present Now", systemImage: "checkmark.circle.fill")
                if selectedFilter == .presentNow {
                    Image(systemName: "checkmark")
                }
            }
            Button {
                adaptiveWithAnimation { filterRaw = "upper" }
            } label: {
                Label("Upper", systemImage: "circle.fill")
                if selectedFilter == .upper {
                    Image(systemName: "checkmark")
                }
            }
            Button {
                adaptiveWithAnimation { filterRaw = "lower" }
            } label: {
                Label("Lower", systemImage: "circle.fill")
                if selectedFilter == .lower {
                    Image(systemName: "checkmark")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Filter")
            }
            .font(AppTheme.ScaledFont.captionSemibold)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Mode Picker

/// Segmented picker for selecting student view mode
struct StudentModePicker: View {
    @Binding var mode: StudentMode

    var body: some View {
        Picker("Mode", selection: $mode) {
            Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
            Label("Open Work", systemImage: "doc.text").tag(StudentMode.workOverview)
            Label("Ages", systemImage: "calendar").tag(StudentMode.age)
            Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
            Label("Needs Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
            Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Add Student Button

/// Reusable add student button with CSV import context menu
struct AddStudentButton: View {
    let onAddStudent: () -> Void
    let onImportCSV: () -> Void

    var body: some View {
        Button {
            onAddStudent()
        } label: {
            Label("Add Student", systemImage: "plus.circle.fill")
        }
        .keyboardShortcut("n", modifiers: [.command])
        .contextMenu {
            Button {
                onImportCSV()
            } label: {
                Label("Import Students from CSV…", systemImage: "arrow.down.doc")
            }
        }
    }
}
