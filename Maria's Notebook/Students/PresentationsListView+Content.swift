// PresentationsListView+Content.swift
// Content rendering extracted from PresentationsListView

import SwiftUI
import CoreData

extension PresentationsListView {
    // MARK: - Content

    var content: some View {
        Group {
            if sort == .upcomingThenPresented {
                upcomingThenPresentedContent
            } else {
                flatSortedContent
            }
        }
    }

    @ViewBuilder
    private var upcomingThenPresentedContent: some View {
        if filter == .hiddenUndated {
            hiddenUndatedContent
        } else {
            defaultFilteredContent
        }
    }

    @ViewBuilder
    private var hiddenUndatedContent: some View {
        if hiddenUndated.isEmpty {
            emptyState(title: "No hidden presentations",
                       message: "Presentations marked presented without a date will appear here.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(icon: "eye.slash.fill", title: "Hidden")
                    presentationGrid(hiddenUndated)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var defaultFilteredContent: some View {
        let showUpcoming: Bool = filter != .completed
        let showPresented: Bool = filter != .notCompleted
        let up: [CDLessonAssignment] = defaultUpcoming
        let gv: [CDLessonAssignment] = defaultPresented

        if (!showUpcoming || up.isEmpty) && (!showPresented || gv.isEmpty) {
            emptyState(title: "No presentations",
                       message: "Try adjusting your filters or add presentations from the Lessons library.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showUpcoming && !up.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(icon: "clock", title: "To Present")
                            presentationGrid(up)
                        }
                    }
                    if showPresented && !gv.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(icon: "checkmark.circle", title: "Given")
                            presentationGrid(gv)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var flatSortedContent: some View {
        if sortedAssignments.isEmpty {
            emptyState(title: "No presentations",
                       message: "Try adjusting your filters or add presentations from the Lessons library.")
        } else {
            ScrollView {
                presentationGrid(sortedAssignments)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(AppTheme.ScaledFont.titleMedium)
            Text(message)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
    }

    private func presentationGrid(_ assignments: [CDLessonAssignment]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(assignments, id: \.id) { sl in
                presentationCardItem(sl)
            }
        }
    }

    private func presentationCardItem(_ sl: CDLessonAssignment) -> some View {
        PresentationCard(
            snapshot: sl.snapshot(),
            lesson: lessonMap[uuidString: sl.lessonID],
            students: students
        )
        .onTapGesture { selectedLessonID = sl.id }
        .contextMenu {
            Button {
                quickActionsLessonID = sl.id
            } label: {
                Label("Quick Actions…", systemImage: "bolt")
            }
        }
    }
}
