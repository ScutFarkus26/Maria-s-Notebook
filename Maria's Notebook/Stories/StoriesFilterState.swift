import Foundation
import SwiftUI

@Observable
@MainActor
final class StoriesFilterState {
    var searchText: String = "" {
        didSet { scheduleDebounce() }
    }
    private(set) var debouncedSearchText: String = ""

    /// Selected themes — a story matches if it contains ALL selected themes (AND).
    var selectedThemes: Set<String> = []

    /// Optional grade-band filter from `StoryGradeBand.filterBuckets`.
    var selectedGradeBand: StoryGradeBand?

    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(200)

    init() {
        debouncedSearchText = searchText
    }

    func clearAll() {
        searchText = ""
        debouncedSearchText = ""
        selectedThemes.removeAll()
        selectedGradeBand = nil
    }

    var hasActiveFilters: Bool {
        !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedThemes.isEmpty
            || selectedGradeBand != nil
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: debounceInterval)
                debouncedSearchText = searchText
            } catch {
                // Cancelled — ignore.
            }
        }
    }
}
