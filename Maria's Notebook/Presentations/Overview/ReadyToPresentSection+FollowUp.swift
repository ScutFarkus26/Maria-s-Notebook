// ReadyToPresentSection+FollowUp.swift
// The Follow Up pill's slice: lessons already given that still carry an
// unresolved responsibility.
//
// The groups are built once per change into `followUpGroups` rather than per
// `body` pass. `FollowingPresentationsService.groups` builds three lookup
// dictionaries over every assignment, lesson and student before it groups
// anything, and this pane reads the result twice — once for the pill's count,
// once for the list — so recomputing it inline would pay that cost on every
// keystroke in the search field.

import CoreData
import SwiftUI

extension ReadyToPresentSection {

    /// Cheap value that changes when the groups would.
    ///
    /// The cache sizes are in here because the view model fills its caches
    /// asynchronously: the first render can see rows but no assignments, and
    /// without this the groups would stay stuck on that first, nameless build.
    struct FollowUpTrigger: Equatable {
        let rowIDs: [NSManagedObjectID]
        let searchText: String
        let studentFilter: UUID?
        let cachedAssignments: Int
        let cachedStudents: Int
    }

    var followUpTrigger: FollowUpTrigger {
        FollowUpTrigger(
            rowIDs: followUpRows.map(\.objectID),
            searchText: filterState.debouncedSearchText,
            studentFilter: coordinator.selectedStudentFilter,
            cachedAssignments: viewModel.cachedLessonAssignments.count,
            cachedStudents: viewModel.cachedStudents.count
        )
    }

    func rebuildFollowUpGroups() {
        followUpGroups = FollowingPresentationsService.groups(
            rows: Array(followUpRows),
            // All three come from the view model's caches, which already hold
            // every assignment, lesson and visible student — the alternative is
            // three more `@FetchRequest`s over the same tables.
            assignments: viewModel.cachedLessonAssignments,
            lessons: viewModel.lessons,
            students: viewModel.cachedStudents,
            studentID: coordinator.selectedStudentFilter,
            searchText: filterState.debouncedSearchText,
            context: viewContext
        )
    }

    @ViewBuilder
    var followUpContent: some View {
        if followUpGroups.isEmpty {
            ContentUnavailableView(
                "Nothing to Follow",
                systemImage: "eye.circle",
                description: Text(
                    "Every presentation you have given has been observed or decided on."
                )
            )
            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
        } else {
            PresentationFollowUpList(
                groups: followUpGroups,
                focusedPresentationID: suggestedLessonID,
                onOpen: { coordinator.showLessonAssignmentDetail($0) }
            )
            .padding(.top, AppTheme.Spacing.compact)
        }
    }
}
