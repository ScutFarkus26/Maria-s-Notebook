// PresentationsFilterState.swift
// Search + chip state for the Ready-to-Present grid, owned by the Lessons &
// Work workspace and fed from its search field.

import Foundation
import SwiftUI

@Observable
final class PresentationsFilterState {
    /// Live text in the search field.
    var searchText: String = ""

    /// Debounced search text — what the grid actually filters against.
    var debouncedSearchText: String = ""

    /// Active filter chip for the Ready-to-Present section. `.all` is the default
    /// (unfiltered) state and is what we land on after re-tapping the active chip.
    var selectedChip: PresentationsFilterChip = .all

    private var debounceTask: Task<Void, Never>?

    func updateSearchText(_ new: String) {
        searchText = new
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.debouncedSearchText = new
        }
    }
}
