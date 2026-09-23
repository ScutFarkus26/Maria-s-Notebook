// ReadyToPresentSection+Slices.swift
// What each Presentations pill holds, and how many.
//
// Split out of the section itself so the view file stays about layout: these
// are pure derivations over `PresentationsViewModel`, and every one of them is
// narrowed by the same student filter and search text the visible grid is.

import CoreData
import SwiftUI

// MARK: - One render's slices

/// Every list the pills and the grid read, computed once per `body` pass and
/// passed down as values. The pill row alone used to rebuild the ready and
/// brewing lists four times, and the grid, the scroll trigger and the
/// selection pruner rebuilt them again.
struct ReadyToPresentSlices {
    let ready: [CDLessonAssignment]
    let blocked: [CDLessonAssignment]
    let overdue: [CDLessonAssignment]
    let recentlyMissed: [CDLessonAssignment]
    let followUpCount: Int

    /// Blocked first, then ready — the order the All pill renders them in.
    var visible: [CDLessonAssignment] { blocked + ready }

    func count(_ chip: PresentationsFilterChip) -> Int {
        switch chip {
        case .all:
            return ready.count + blocked.count
        case .followUp:
            return followUpCount
        case .suggestedNext:
            // `rankedSuggestions` returns the top `suggestedNextLimit` of the
            // ready list, so its count is known without scoring anything.
            return min(ready.count, PresentationsViewModel.suggestedNextLimit)
        case .waitingForWork:
            return blocked.count
        case .overdue:
            return overdue.count
        case .recentlyMissed:
            return recentlyMissed.count
        }
    }
}

extension ReadyToPresentSection {

    /// This render's slices. Call once per `body` pass.
    func makeSlices() -> ReadyToPresentSlices {
        ReadyToPresentSlices(
            ready: filteredAndSortedReadyLessons,
            blocked: filteredAndSortedBlockedLessons,
            overdue: overdueSlice,
            recentlyMissed: recentlyMissedSlice,
            followUpCount: followUpGroups.count
        )
    }

    func suggestedNextSlice(among ready: [CDLessonAssignment]) -> [SuggestedPresentation] {
        viewModel.rankedSuggestions(
            among: ready,
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
