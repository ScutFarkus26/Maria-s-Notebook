// PresentationsFilterState.swift
// View-state container shared between the Presentations header and the
// Ready-to-Present grid. Owns text-search state and (in later phases)
// the active filter chip.

import Foundation
import SwiftUI

@Observable
@MainActor
final class PresentationsFilterState {
    /// Live text in the search field.
    var searchText: String = ""

    /// Debounced search text — what the grid actually filters against.
    var debouncedSearchText: String = ""

    /// Committed search tokens (lowercased). All must match in addition to `debouncedSearchText`.
    var committedFilters: [String] = []

    /// Active filter chip for the Ready-to-Present section. `.all` is the default
    /// (unfiltered) state and is what we land on after re-tapping the active chip.
    var selectedChip: PresentationsFilterChip = .all

    /// When true, hide presentations whose students already appear on a
    /// presentation scheduled for today. Toggled from the header.
    var hideStudentsScheduledToday: Bool = false

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

    func commitCurrentSearchAsFilter() {
        let trimmed = searchText.trimmed().lowercased()
        guard !trimmed.isEmpty else { return }
        if !committedFilters.contains(trimmed) {
            committedFilters.append(trimmed)
        }
        searchText = ""
        debouncedSearchText = ""
        debounceTask?.cancel()
    }

    func removeFilter(_ token: String) {
        committedFilters.removeAll { $0 == token }
    }

    func clearFilters() {
        committedFilters.removeAll()
    }

    func popLastFilter() {
        guard !committedFilters.isEmpty else { return }
        committedFilters.removeLast()
    }
}
