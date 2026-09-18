// LessonsAndWorkPresentationsView.swift
// The Presentations half of the Lessons & Work workspace.
//
// Who has waited longest, beside what you could give them — so choosing a
// child and choosing a lesson never costs a screen change, and the Scheduled
// calendar stays pinned below to drop onto.
//
// This was `LessonsAndWorkToScheduleView`, which carried a Presentations /
// Work segmented picker of its own. That picker is now the workspace's
// top-level one, so this view is only ever presentations and the state slices
// it used to be reached through — ready, brewing, overdue, and the follow-ups
// that lived in the Attention tab — are the pill row inside it.

import CoreData
import SwiftUI

struct LessonsAndWorkPresentationsView: View {
    let searchText: String
    let focusedPresentationID: UUID?
    let selection: WorkspaceMultiSelection
    /// Children with a lesson on the calendar from today onward, computed once
    /// per refresh by the workspace rather than re-derived per row.
    let studentIDsWithUpcomingLessons: Set<UUID>

    @Environment(\.dependencies) private var dependencies
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Owned here so the waiting rail and the presentations it narrows share one
    /// student filter and one search.
    @State private var coordinator = PresentationsCoordinator()
    @State private var filterState = PresentationsFilterState()

    var body: some View {
        #if os(macOS)
        railAndPresentations
        #else
        if horizontalSizeClass == .regular {
            railAndPresentations
        } else {
            VStack(spacing: 0) {
                // No room for a column on a phone, so the same list lies on its
                // side above the lessons rather than becoming another tab.
                WaitingStudentsStrip(
                    viewModel: dependencies.presentationsViewModel,
                    coordinator: coordinator,
                    filterState: filterState,
                    studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
                )
                Divider()
                presentations
            }
        }
        #endif
    }

    private var railAndPresentations: some View {
        HStack(spacing: 0) {
            waitingStudentsRail
                .frame(width: StudentColumn.preferredWidth)
            Divider()
            presentations
                .frame(maxWidth: .infinity)
        }
    }

    private var waitingStudentsRail: some View {
        WaitingStudentsRail(
            viewModel: dependencies.presentationsViewModel,
            coordinator: coordinator,
            filterState: filterState,
            studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
        )
    }

    private var presentations: some View {
        PresentationsView(
            embeddedSearchText: searchText,
            focusedPresentationID: focusedPresentationID,
            coordinator: coordinator,
            filterState: filterState,
            selection: selection
        )
    }
}
