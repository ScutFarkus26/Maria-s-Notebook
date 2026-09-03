//
//  StudentNotesTimelineView+Filtering.swift
//  Maria's Notebook
//
//  Extracted from StudentNotesTimelineView.swift
//

import SwiftUI
import CoreData

// MARK: - Filtering & Tag Logic

extension StudentNotesTimelineList {

    /// All unique tag strings used across current items
    var allUsedTags: [String] {
        let tagSet = Set(viewModel.items.flatMap { $0.tags })
        return tagSet.sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
    }

    var allFilteredItems: [UnifiedNoteItem] {
        var items = viewModel.items

        // School-year lens: scope the timeline to notes in the selected year
        // (no-op when the lens is "All years").
        if let range = dependencies.schoolYearStore.activeRange {
            items = items.filter { range.contains($0.date) }
        }

        // Apply report filter
        if selectedFilter == .reportItems {
            items = items.filter(\.includeInReport)
        } else if selectedFilter == .followUp {
            items = items.filter(\.needsFollowUp)
        }

        // Apply tag filter
        if !selectedFilterTags.isEmpty {
            items = items.filter { item in
                !selectedFilterTags.isDisjoint(with: item.tags)
            }
        }

        // Apply search filter
        if !debouncedSearchText.isEmpty {
            let searchLower = debouncedSearchText.lowercased()
            items = items.filter {
                $0.body.localizedCaseInsensitiveContains(searchLower) ||
                $0.contextText.localizedCaseInsensitiveContains(searchLower)
            }
        }

        return items
    }

    /// The filtered list as the body needs it, derived once per pass.
    ///
    /// `allFilteredItems` runs four filter passes (two of them substring
    /// searches over every note body). The list body reads it, directly and
    /// through `pinned`/`grouped`/`hasMore`, five or six times per evaluation
    /// — on every keystroke in the search field — so it's computed once here
    /// and threaded through.
    struct DisplayedItems {
        let displayed: [UnifiedNoteItem]
        let pinned: [UnifiedNoteItem]
        let grouped: [(key: String, items: [UnifiedNoteItem])]
        let remainingCount: Int

        var hasMore: Bool { remainingCount > 0 }
    }

    func makeDisplayedItems() -> DisplayedItems {
        let all = allFilteredItems
        let displayed = Array(all.prefix(displayedCount))
        return DisplayedItems(
            displayed: displayed,
            pinned: displayed.filter(\.isPinned),
            grouped: groupedItems(from: displayed.filter { !$0.isPinned }),
            remainingCount: max(0, all.count - displayedCount)
        )
    }

    var hasActiveFilters: Bool {
        !selectedFilterTags.isEmpty || !debouncedSearchText.isEmpty || selectedFilter != .all
    }

    // Group unpinned items by month and year
    private func groupedItems(from items: [UnifiedNoteItem]) -> [(key: String, items: [UnifiedNoteItem])] {
        let grouped = items.grouped { monthYearKey(for: $0.date) }
        .mapValues { items in
            items.sorted { $0.date > $1.date } // Sort items within each sequence (newest first)
        }

        // Sort groups by date (newest first)
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            // Parse the keys to compare dates properly
            key1 > key2
        }

        return sortedKeys.map { key in
            (key: key, items: grouped[key] ?? [])
        }
    }

    func monthYearKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    func monthYearHeader(for key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return key
        }

        let dateComponents = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: dateComponents) else {
            return key
        }

        return DateFormatters.monthYear.string(from: date)
    }

    func loadMoreItems() {
        let newCount = min(displayedCount + pageSize, allFilteredItems.count)
        adaptiveWithAnimation {
            displayedCount = newCount
        }
    }

    func resetPagination() {
        displayedCount = pageSize
    }

    // MARK: - Tag Filter Section

    var tagFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allUsedTags, id: \.self) { tag in
                    Button {
                        adaptiveWithAnimation {
                            if selectedFilterTags.contains(tag) {
                                selectedFilterTags.remove(tag)
                            } else {
                                selectedFilterTags.insert(tag)
                            }
                            resetPagination()
                        }
                    } label: {
                        TagBadge(tag: tag, compact: true)
                            .opacity(selectedFilterTags.contains(tag) ? 1.0 : 0.5)
                    }
                    .buttonStyle(.plain)
                }

                // Clear all button
                if !selectedFilterTags.isEmpty {
                    Button {
                        adaptiveWithAnimation {
                            selectedFilterTags.removeAll()
                            resetPagination()
                        }
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
    }

    // MARK: - Active Filters Summary

    var activeFiltersSummary: some View {
        HStack {
            Text("Showing \(allFilteredItems.count) of \(viewModel.items.count) notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                adaptiveWithAnimation {
                    searchText = ""
                    debouncedSearchText = ""
                    selectedFilterTags.removeAll()
                    selectedFilter = .all
                    resetPagination()
                }
            } label: {
                Text("Clear All")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
    }
}
