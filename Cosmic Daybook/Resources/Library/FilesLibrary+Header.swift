import SwiftUI

// The Files list's header: search, Select and Add File, the quick views,
// category and tag menus, and the select bar that replaces them in select mode.
extension FilesLibrary {

    var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSelectMode {
                selectBar
            } else {
                HStack(spacing: 12) {
                    LibrarySearchField(prompt: "Search files", text: $searchText)
                    Spacer(minLength: 0)
                    if !allResources.isEmpty {
                        Button("Select") {
                            isSelectMode = true
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        isShowingImportSheet = true
                    } label: {
                        Label("Add File", systemImage: SFSymbol.Action.plus)
                    }
                    .buttonStyle(.borderedProminent)
                }
                filterRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickViewChip(.all, count: allResources.count)
                quickViewChip(.favorites, count: allResources.filter(\.isFavorite).count)
                quickViewChip(
                    .recents,
                    count: min(allResources.filter { $0.lastViewedAt != nil }.count, ResourceLibraryFilter.recentsLimit)
                )
                Divider().frame(height: 16)
                categoryMenu
                if !allUsedTags.isEmpty {
                    tagMenu
                }
                if hasActiveFilter {
                    Button("Clear", action: clearFilters)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func quickViewChip(_ filter: ResourceSmartFilter, count: Int) -> some View {
        let isSelected = smartFilter == filter
        return Button {
            smartFilter = filter
        } label: {
            Text("\(filter.displayName) \(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .capsuleFill(
                    isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.subtle)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var categoryMenu: some View {
        Menu {
            Button("All Categories") {
                selectedCategory = nil
            }
            Divider()
            ForEach(categoriesWithCounts, id: \.category) { item in
                Button {
                    selectedCategory = item.category
                } label: {
                    Label("\(item.category.rawValue) (\(item.count))", systemImage: item.category.icon)
                }
            }
        } label: {
            Label(
                selectedCategory?.rawValue ?? "All Categories",
                systemImage: selectedCategory?.icon ?? "folder"
            )
            .font(.caption.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    private var tagMenu: some View {
        Menu {
            Button("All Tags") {
                selectedTagFilter = nil
            }
            Divider()
            ForEach(allUsedTags, id: \.self) { tag in
                Button(TagHelper.tagName(tag)) {
                    selectedTagFilter = tag
                }
            }
        } label: {
            Label(
                selectedTagFilter.map { TagHelper.tagName($0) } ?? "All Tags",
                systemImage: "tag"
            )
            .font(.caption.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    /// Every category that holds a file, with its count.
    private var categoriesWithCounts: [(category: ResourceCategory, count: Int)] {
        let grouped = Dictionary(grouping: allResources, by: \.category)
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return (category: category, count: resources.count)
        }
    }

    /// Every tag used on a file, once, in name order.
    private var allUsedTags: [String] {
        var seen = Set<String>()
        var uniqueTags: [String] = []
        for resource in allResources {
            for tag in resource.tagsArray where seen.insert(TagHelper.tagName(tag).lowercased()).inserted {
                uniqueTags.append(tag)
            }
        }
        return uniqueTags.sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
    }

    // MARK: - Select bar

    private var selectBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedCount) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(resourceSelection.allVisibleSelected ? "Deselect All" : "Select All") {
                selectedObjectIDs = resourceSelection.togglingAll()
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
            Menu {
                Button("Favorite", systemImage: SFSymbol.Shape.starFill) {
                    bulkToggleFavorite()
                }
                Button("Categorize", systemImage: "folder") {
                    isShowingBulkCategoryPicker = true
                }
                Button("Tag", systemImage: "tag") {
                    bulkTags = []
                    isShowingBulkTagPicker = true
                }
                Divider()
                Button("Delete", systemImage: SFSymbol.Action.trash, role: .destructive) {
                    isShowingBulkDeleteConfirmation = true
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(selectedCount == 0)
            Button("Done") {
                exitSelectMode()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 34)
    }
}
