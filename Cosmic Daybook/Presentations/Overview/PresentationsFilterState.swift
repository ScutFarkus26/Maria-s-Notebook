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

    /// What the Ready-to-Present section shows: a state segment, or a flag on
    /// Ready. `.ready` is the default, and where turning a flag off lands.
    var selectedChip: PresentationsFilterChip = .ready

    private var debounceTask: Task<Void, Never>?

    func updateSearchText(_ new: String) {
        searchText = new
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.debouncedSearchText = new
        }
    }
}
