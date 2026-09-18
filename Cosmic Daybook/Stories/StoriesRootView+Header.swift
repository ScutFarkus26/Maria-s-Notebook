import SwiftUI

extension StoriesRootView {
    var headerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Stories")
                    .font(.title2.bold())
                Spacer()
                if importQueue.pendingCount > 0 {
                    Label(
                        "Analyzing \(importQueue.completedInBatch + 1) of \(importQueue.batchSize)…",
                        systemImage: "wand.and.stars"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("Add PDF", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                searchField
                if filterState.hasActiveFilters {
                    Button("Clear") {
                        filterState.clearAll()
                    }
                    .buttonStyle(.borderless)
                }
            }
            filterChipBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search stories", text: Binding(
                get: { filterState.searchText },
                set: { filterState.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            if !filterState.searchText.isEmpty {
                Button {
                    filterState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    var filterChipBar: some View {
        let themesUniverse = viewModel.themesUniverse(from: Array(stories))
        if !themesUniverse.isEmpty || !StoryGradeBand.filterBuckets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StoryGradeBand.filterBuckets, id: \.self) { band in
                        let isSelected = filterState.selectedGradeBand == band
                        StoryThemeChip(
                            band.displayName,
                            variant: .selectable(isSelected: isSelected) {
                                filterState.selectedGradeBand = isSelected ? nil : band
                            }
                        )
                    }
                    if !themesUniverse.isEmpty {
                        Divider().frame(height: 16)
                    }
                    ForEach(themesUniverse, id: \.self) { theme in
                        let isSelected = filterState.selectedThemes.contains(theme)
                        StoryThemeChip(
                            theme,
                            variant: .selectable(isSelected: isSelected) {
                                if isSelected {
                                    filterState.selectedThemes.remove(theme)
                                } else {
                                    filterState.selectedThemes.insert(theme)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
