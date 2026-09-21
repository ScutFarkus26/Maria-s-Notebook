//
//  LessonAssignmentHistoryView+Filters.swift
//  Cosmic Daybook
//
//  Filter bar UI for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import CoreData

extension LessonAssignmentHistoryView {

    // MARK: - Filter Bar

    var filterBar: some View {
        HStack(spacing: 12) {
            MultiSelectFilterMenu(
                items: safeStudents,
                selection: $selectedStudentIDs,
                id: { $0.id },
                label: { displayName(for: $0) },
                summary: FilterSelectionSummary(allLabel: "All Students"),
                systemImage: "person.3"
            )

            MultiSelectFilterMenu(
                items: availableAreas,
                selection: $selectedAreas,
                label: { $0 },
                summary: FilterSelectionSummary(allLabel: "All Areas"),
                systemImage: "line.3.horizontal.decrease.circle"
            )

            Spacer()
        }
        .padding(.horizontal, 12)
    }
}
