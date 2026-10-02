// ChecklistFilterBar.swift
// The checklist grid's row and column filters.
//
// The text field hides lesson rows that don't match; the student button hides the
// columns of students that weren't picked. Both are display-only. iPhone only: the
// Mac and iPad carry both in the toolbar (ClassAreaChecklistView+Toolbar.swift).

import SwiftUI
import CoreData

struct ChecklistFilterBar: View {
    @Binding var lessonQuery: String
    @Binding var studentFilterIDs: Set<UUID>
    /// Every student available to filter to — already narrowed to the enrolled,
    /// non-test roster by the caller.
    let rosterStudents: [CDStudent]
    /// The students currently pinned, in roster order. Empty when unfiltered.
    let selectedStudents: [CDStudent]
    let displayName: (CDStudent) -> String
    let summary: String?
    let onQueryDebounced: (String) -> Void
    let onClearAll: () -> Void

    private var hasActiveFilters: Bool {
        !lessonQuery.trimmed().isEmpty || !studentFilterIDs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            HStack(spacing: AppTheme.Spacing.small) {
                DebouncedSearchField(
                    "Filter lessons",
                    text: $lessonQuery,
                    onDebouncedChange: onQueryDebounced
                )
                .frame(minWidth: 140)

                studentFilterButton

                if hasActiveFilters {
                    Button("Clear", action: onClearAll)
                        .buttonStyle(.borderless)
                        .help("Show every lesson and student again")
                }
            }

            if !selectedStudents.isEmpty {
                SelectedStudentChipsRow(students: selectedStudents, label: displayName) { student in
                    guard let id = student.id else { return }
                    studentFilterIDs.remove(id)
                }
            }

            if let summary {
                Text(summary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.Spacing.small)
        .backgroundPlatform()
        .adaptiveAnimation(.snappy(duration: 0.2), value: studentFilterIDs)
    }

    private var studentFilterButton: some View {
        ChecklistStudentFilterButton(studentFilterIDs: $studentFilterIDs, rosterStudents: rosterStudents)
            .buttonStyle(.bordered)
            .tint(studentFilterIDs.isEmpty ? nil : Color.accentColor)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ChecklistFilterBarPreview: View {
    var body: some View {
        struct Demo: View {
            @State private var query: String = ""
            @State private var studentFilterIDs: Set<UUID> = []

            var body: some View {
                VStack(spacing: 0) {
                    ChecklistFilterBar(
                        lessonQuery: $query,
                        studentFilterIDs: $studentFilterIDs,
                        rosterStudents: [],
                        selectedStudents: [],
                        displayName: { $0.firstName },
                        summary: query.trimmed().isEmpty ? nil : "3 of 27 lessons",
                        onQueryDebounced: { _ in },
                        onClearAll: { query = "" }
                    )
                    Divider()
                    Spacer()
                }
                .frame(width: 520, height: 200)
            }
        }
        return Demo()
    }
}

#Preview("Checklist Filters") {
    ChecklistFilterBarPreview()
}
