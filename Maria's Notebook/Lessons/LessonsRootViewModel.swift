// Maria's Notebook/Lessons/LessonsRootViewModel.swift
// Replace to remove the Published-update warning source. (This view model is no longer necessary.)

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class LessonsRootViewModel {
    init() { }

    // Keep as a pure helper if anything still calls it.
    func filteredLessons(modelContext: ModelContext, filterState: LessonsFilterState, using filterer: LessonsViewModel) -> [Lesson] {
        filterer.filteredLessons(
            modelContext: modelContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: filterState.debouncedSearchText,
            selectedSubject: filterState.selectedSubject,
            selectedGroup: filterState.selectedGroup
        )
    }
}
