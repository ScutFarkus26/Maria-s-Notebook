// ClassGridChecklistView+Toolbar.swift
// The Mac and regular-width iPad Checklist: the lens (All marks / Ready) and Jump to
// sequence in the toolbar, beside the Class Grid's own area menu, search and children
// filter (ClassGridView.swift).
// No Select button: cells are selected with ⌘- and Shift-click, a drag, or Select ready.
// The iPhone has Select and the lens menu in its navigation bar (ClassGridChecklistView.swift).

import SwiftUI

/// One pick from "Jump to sequence". A fresh token per pick, so picking the same
/// band twice scrolls twice.
struct ChecklistSequenceJump: Equatable {
    let sequence: String
    let token = UUID()
}

extension ClassGridChecklistView {

    /// The active filters' row over the grid, the grid, and the lens and Jump to
    /// sequence in the toolbar. The Class Grid owns the page's stack and title.
    var regularPage: some View {
        VStack(spacing: 0) {
            if let summary = viewModel.filterSummary {
                activeFiltersRow(summary: summary)
                Divider()
            }
            checklistBody
        }
        .background(ChecklistGridMetrics.surface)
        .toolbar { regularToolbar }
    }

    @ToolbarContentBuilder
    private var regularToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            jumpToSequenceMenu
        }
        ToolbarItem(placement: .primaryAction) {
            ChecklistLensPicker(lens: $viewModel.lens, readyCount: viewModel.readyTotal)
        }
    }

    private var jumpToSequenceMenu: some View {
        Menu {
            ForEach(viewModel.visibleSequences, id: \.self) { sequence in
                Button(sequence.isEmpty ? "Other" : sequence) {
                    sequenceJump = ChecklistSequenceJump(sequence: sequence)
                }
            }
        } label: {
            Label("Jump to Sequence", systemImage: "list.bullet.indent")
        }
        .disabled(viewModel.visibleSequences.isEmpty)
        .help("Scroll to a sequence, opening it if it's collapsed")
    }

    /// Shown only while a filter is on: what's hidden, the picked children, and Clear.
    /// The iPhone shows it too, over its grid (ClassGridChecklistView.swift).
    func activeFiltersRow(summary: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text(summary)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize()

            if !viewModel.selectedFilterStudents.isEmpty {
                SelectedStudentChipsRow(students: viewModel.selectedFilterStudents) { student in
                    guard let id = student.id else { return }
                    viewModel.studentFilterIDs.remove(id)
                }
            } else {
                Spacer(minLength: 0)
            }

            Button("Clear") {
                viewModel.clearFilters(context: viewContext)
            }
            .buttonStyle(.borderless)
            .help("Show every lesson and student again")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
