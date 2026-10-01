// ReadyToPresentSection+Slices.swift
// What each state and flag holds, and how many rows that makes.
//
// Split out of the section itself so the view file stays about layout: these
// are pure derivations over `PresentationsViewModel`, and every one of them is
// narrowed by the same student filter and search text the visible list is.
//
// How they relate, which is what makes the counts honest:
// - Ready and Brewing partition the unscheduled inbox; Follow Up is given
//   lessons, so the three segments never share a record.
// - Overdue is the ready lessons older than 14 school days — a subset of
//   Ready, filtered by the same student and search.
// - Missed is lessons that were *scheduled* in the last 14 days and not given
//   because a child was absent. Being scheduled, none of them is in Ready; the
//   flag gathers them back into the backlog so they can be dragged onto a new
//   day, which is why it sits with Ready's flags rather than being a state.

import CoreData
import SwiftUI

// MARK: - One render's slices

/// Every list the filter bar and the backlog read, computed once per `body`
/// pass and passed down as values. The pill row alone used to rebuild the
/// ready and brewing lists four times, and the grid, the scroll trigger and
/// the selection pruner rebuilt them again.
struct ReadyToPresentSlices {
    let ready: [CDLessonAssignment]
    let blocked: [CDLessonAssignment]
    let overdue: [CDLessonAssignment]
    let recentlyMissed: [CDLessonAssignment]
    let followUpCount: Int

    /// The presentations on screen under `chip` — what a selection can hold
    /// and a deep link can scroll to. Follow Up's rows are given lessons with
    /// their own ids, carried separately.
    func visible(for chip: PresentationsFilterChip) -> [CDLessonAssignment] {
        switch chip {
        case .ready, .suggestedNext: return ready
        case .waitingForWork: return blocked
        case .overdue: return overdue
        case .recentlyMissed: return recentlyMissed
        case .followUp: return []
        }
    }

    /// The number beside each segment and flag: rows, which is to say
    /// lessons, since a lesson planned for several groups is one row.
    func count(_ chip: PresentationsFilterChip) -> Int {
        switch chip {
        case .followUp:
            return followUpCount
        case .suggestedNext:
            // `rankedSuggestions` returns the top `suggestedNextLimit` of the
            // ready list, so its count is known without scoring anything.
            return min(ready.count, PresentationsViewModel.suggestedNextLimit)
        case .ready, .waitingForWork, .overdue, .recentlyMissed:
            return ReadyBacklog.lessonCount(visible(for: chip), lessonID: \.resolvedLessonID)
        }
    }
}

/// Where a deep-linked presentation sits in the inbox, once the view model
/// knows. The reveal in `PresentationsView` can run before the first load, so
/// the section finishes the job when the answer arrives.
struct BacklogFocusPlacement: Equatable {
    let id: UUID
    let isBrewing: Bool
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

    func focusPlacement(in slices: ReadyToPresentSlices) -> BacklogFocusPlacement? {
        guard let id = focusedLessonID else { return nil }
        if slices.blocked.contains(where: { $0.id == id }) {
            return BacklogFocusPlacement(id: id, isBrewing: true)
        }
        if slices.ready.contains(where: { $0.id == id }) {
            return BacklogFocusPlacement(id: id, isBrewing: false)
        }
        return nil
    }

    /// Moves to the state that shows the deep-linked presentation, unless the
    /// current one already does. Runs only when the placement changes, so the
    /// guide can still leave it.
    func reveal(_ placement: BacklogFocusPlacement?, in slices: ReadyToPresentSlices) {
        guard let placement else { return }
        let current = filterState.selectedChip
        guard !slices.visible(for: current).contains(where: { $0.id == placement.id }) else { return }
        filterState.selectedChip = placement.isBrewing ? .waitingForWork : .ready
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

    /// What the menu, the bulk action and the deletion pruner act on: the
    /// presentations under the current state or flag. Only reached from those
    /// actions, never per row per render.
    var currentlyVisibleAssignments: [CDLessonAssignment] {
        makeSlices().visible(for: filterState.selectedChip)
    }
}
