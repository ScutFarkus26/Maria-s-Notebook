// PresentationsInboxView+Sidebar.swift
// Trailing sidebar slot on the regular (macOS/iPad) layout. Delegates to the
// standalone `StudentsNeedingLessonsView` so the same list can be reused as a
// full-screen tab in the compact layout.

import SwiftUI
import CoreData

extension PresentationsInboxView {
    @ViewBuilder
    var studentsNeedingLessonsSidebar: some View {
        StudentsNeedingLessonsView(
            viewModel: viewModel,
            coordinator: coordinator,
            filterState: filterState,
            lessonAssignments: Array(lessonAssignments),
            showAboutCard: true
        )
        .frame(width: 220)
    }
}
