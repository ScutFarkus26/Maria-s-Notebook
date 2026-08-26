// ClassAreaChecklistView+Filters.swift
// The checklist's filter bar and the empty state it can produce.

import SwiftUI
import CoreData

// MARK: - Filters

extension ClassAreaChecklistView {
    var filterBar: some View {
        ChecklistFilterBar(
            lessonQuery: $viewModel.lessonQuery,
            studentFilterIDs: $viewModel.studentFilterIDs,
            rosterStudents: viewModel.rosterStudents,
            selectedStudents: viewModel.selectedFilterStudents,
            displayName: { viewModel.displayName(for: $0) },
            summary: viewModel.filterSummary,
            onQueryDebounced: { query in
                viewModel.applyLessonQuery(query, context: viewContext)
            },
            onClearAll: {
                viewModel.clearFilters(context: viewContext)
            }
        )
    }

    /// Shown in place of the grid when no row survives — either the filter matched
    /// nothing or the area itself is empty.
    @ViewBuilder
    var emptyState: some View {
        if viewModel.appliedLessonQuery.isEmpty {
            ContentUnavailableView(
                "No Lessons",
                systemImage: "books.vertical",
                description: Text("There are no lessons in \(areaLabel) yet.")
            )
        } else {
            ContentUnavailableView {
                Label("No Matching Lessons", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing in \(areaLabel) matches \u{201C}\(viewModel.appliedLessonQuery)\u{201D}.")
            } actions: {
                // The grid only ever shows one area, so point at the areas that do match
                // rather than making the guide hunt through the picker.
                ForEach(viewModel.otherAreaMatches) { match in
                    Button("\(match.area) (\(match.count))") {
                        viewModel.selectedArea = match.area
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear Filter") {
                    viewModel.clearFilters(context: viewContext)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var areaLabel: String {
        let area = viewModel.selectedArea.trimmed()
        return area.isEmpty ? "this area" : area
    }
}
