// ObservationsView+Filtering.swift
// Filter bar UI for ObservationsView

import SwiftUI
import SwiftData

extension ObservationsView {
    // MARK: - Filters UI

    var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ObservationsFilterService.ScopeFilter.allCases) { sf in
                    Button(action: { selectedScope = sf }) {
                        HStack {
                            if selectedScope == sf {
                                Image(systemName: "checkmark")
                            }
                            Text(sf.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedScope.rawValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Menu {
                Button("All Tags") {
                    selectedFilterTags.removeAll()
                }

                Divider()

                let allUsedTags = Set(loadedItems.flatMap { $0.tags }).sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
                ForEach(allUsedTags, id: \.self) { tag in
                    Button(action: {
                        if selectedFilterTags.contains(tag) {
                            selectedFilterTags.remove(tag)
                        } else {
                            selectedFilterTags.insert(tag)
                        }
                    }) {
                        HStack {
                            if selectedFilterTags.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                            Text(TagHelper.tagName(tag))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedFilterTags.isEmpty ? "All Tags" : "\(selectedFilterTags.count) tag\(selectedFilterTags.count == 1 ? "" : "s")")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Filtered Items

    var filteredItems: [UnifiedObservationItem] {
        ObservationsFilterService.filter(
            items: loadedItems,
            filterTags: selectedFilterTags,
            scope: selectedScope,
            searchText: searchText
        )
    }
}
