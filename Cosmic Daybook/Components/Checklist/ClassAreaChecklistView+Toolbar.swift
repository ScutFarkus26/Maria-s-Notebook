// ClassAreaChecklistView+Toolbar.swift
// The Mac and regular-width iPad page: the area as the title's menu ("Checklist · Math"),
// the lens (All Marks / Ready to Present), Jump to sequence, the students filter and the
// lesson search, all in the toolbar.
// No Select button: cells are selected with ⌘- and Shift-click, a drag, or Select ready.
// The iPhone keeps its header and filter bar (ClassSubjectChecklistView.swift).

import SwiftUI

/// One pick from "Jump to sequence". A fresh token per pick, so picking the same
/// band twice scrolls twice.
struct ChecklistSequenceJump: Equatable {
    let sequence: String
    let token = UUID()
}

extension ClassAreaChecklistView {

    /// The iPad gives a sidebar page no navigation bar, so the page brings its own
    /// stack for the toolbar (none when pushed into the iPad mini's More stack).
    /// The Mac's split view already has one.
    var regularPage: some View {
        #if os(macOS)
        regularContent
        #else
        PageNavigationStack { regularContent }
        #endif
    }

    private var regularContent: some View {
        VStack(spacing: 0) {
            if let summary = viewModel.filterSummary {
                activeFiltersRow(summary: summary)
                Divider()
            }
            checklistBody
        }
        .background(ChecklistGridMetrics.surface)
        .navigationTitle(titleText)
        .modifier(ChecklistAreaTitleMenu(
            title: titleText,
            areas: viewModel.availableAreas,
            selection: $viewModel.selectedArea
        ))
        .toolbar { regularToolbar }
        .searchable(text: $viewModel.lessonQuery, prompt: Text(searchPrompt))
        .onSubmit(of: .search) {
            viewModel.applyLessonQuery(viewModel.lessonQuery, context: viewContext)
        }
        // The filter bar's field debounced its text; the toolbar's search field doesn't,
        // so the grid waits for typing to pause before it re-filters.
        .task(id: viewModel.lessonQuery) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            viewModel.applyLessonQuery(viewModel.lessonQuery, context: viewContext)
        }
    }

    private var areaName: String { viewModel.selectedArea.trimmed() }

    private var titleText: String {
        areaName.isEmpty ? "Checklist" : "Checklist · \(areaName)"
    }

    private var searchPrompt: String {
        areaName.isEmpty ? "Search lessons" : "Search \(areaName)"
    }

    @ToolbarContentBuilder
    private var regularToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ChecklistLensPicker(lens: $viewModel.lens, readyCount: viewModel.readyTotal)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            jumpToSequenceMenu

            ChecklistStudentFilterButton(
                studentFilterIDs: $viewModel.studentFilterIDs,
                rosterStudents: viewModel.rosterStudents,
                isToolbarItem: true
            )
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
    private func activeFiltersRow(summary: String) -> some View {
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

/// The area picker as the page title's menu. The iPad's title menu draws as
/// "Checklist · Math ⌄"; the Mac has no title menu outside document windows, so there
/// the title becomes a menu button in the navigation area and the plain title is hidden.
private struct ChecklistAreaTitleMenu: ViewModifier {
    let title: String
    let areas: [String]
    @Binding var selection: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        picker
                    } label: {
                        Text(title)
                            .font(.headline)
                    }
                    .menuIndicator(.visible)
                    .help("Choose a curriculum area")
                    .accessibilityLabel("Curriculum area: \(selection)")
                }
            }
        #else
        content
            .inlineNavigationTitle()
            .toolbarTitleMenu { picker }
        #endif
    }

    private var picker: some View {
        Picker("Area", selection: $selection) {
            ForEach(areas, id: \.self) { area in
                Text(area).tag(area)
            }
        }
        .pickerStyle(.inline)
    }
}
