// ChecklistFilterBar.swift
// The checklist grid's row and column filters.
//
// The text field hides lesson rows that don't match; the student button hides the
// columns of students that weren't picked. Both are display-only.

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

    @State private var isShowingStudentPicker = false

    private var hasActiveFilters: Bool {
        !lessonQuery.trimmed().isEmpty || !studentFilterIDs.isEmpty
    }

    private var studentButtonTitle: String {
        studentFilterIDs.isEmpty
            ? "All Students"
            : "\(studentFilterIDs.count) of \(rosterStudents.count)"
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
        Button {
            isShowingStudentPicker = true
        } label: {
            Label(studentButtonTitle, systemImage: "person.2")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(studentFilterIDs.isEmpty ? nil : Color.accentColor)
        .help("Show only the students you pick")
        .accessibilityLabel(
            studentFilterIDs.isEmpty
                ? "Filter students, all students shown"
                : "Filter students, \(studentFilterIDs.count) of \(rosterStudents.count) shown"
        )
        .popover(isPresented: $isShowingStudentPicker, arrowEdge: .bottom) {
            StudentPickerPopover(
                students: rosterStudents,
                selectedIDs: $studentFilterIDs,
                onDone: { isShowingStudentPicker = false },
                allowsCreatingStudents: false
            )
        }
    }
}

#Preview("Checklist Filters") {
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
