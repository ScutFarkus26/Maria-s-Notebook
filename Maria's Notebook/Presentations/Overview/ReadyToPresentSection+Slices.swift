// ReadyToPresentSection+Slices.swift
// What each Presentations pill holds, and how many.
//
// Split out of the section itself so the view file stays about layout: these
// are pure derivations over `PresentationsViewModel`, and every one of them is
// narrowed by the same student filter and search text the visible grid is.

import CoreData
import SwiftUI

// MARK: - Chip counts

extension ReadyToPresentSection {

    func chipCount(_ chip: PresentationsFilterChip) -> Int {
        switch chip {
        case .all:
            return filteredAndSortedReadyLessons.count + filteredAndSortedBlockedLessons.count
        case .followUp:
            return followUpGroups.count
        case .suggestedNext:
            return suggestedNextSlice.count
        case .waitingForWork:
            return filteredAndSortedBlockedLessons.count
        case .overdue:
            return overdueSlice.count
        case .recentlyMissed:
            return recentlyMissedSlice.count
        }
    }

    var suggestedNextSlice: [SuggestedPresentation] {
        viewModel.rankedSuggestions(
            among: filteredAndSortedReadyLessons,
            allLessonAssignments: viewModel.cachedLessonAssignments
        )
    }

    var overdueSlice: [CDLessonAssignment] {
        viewModel.applyStudentAndTextFilters(
            to: viewModel.overdueReady(thresholdSchoolDays: 14),
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText
        )
    }

    var recentlyMissedSlice: [CDLessonAssignment] {
        viewModel.applyStudentAndTextFilters(
            to: viewModel.recentlyMissed(within: 14),
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText
        )
    }
}
