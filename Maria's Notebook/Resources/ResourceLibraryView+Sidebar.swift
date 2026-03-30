// ResourceLibraryView+Sidebar.swift
// Category sidebar, chip filter bar, and category menu for ResourceLibraryView.

import SwiftUI

extension ResourceLibraryView {

    // MARK: - Category Sidebar

    var categorySidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Quick Access
                sidebarButton(
                    label: "All Resources", icon: "tray.2",
                    count: allResources.count,
                    isSelected: smartFilter == .all && selectedCategory == nil && selectedTagFilter == nil
                ) {
                    smartFilter = .all
                    selectedCategory = nil
                    selectedTagFilter = nil
                }

                if favoritesCount > 0 {
                    sidebarButton(
                        label: "Favorites", icon: SFSymbol.Shape.starFill,
                        count: favoritesCount,
                        isSelected: smartFilter == .favorites
                    ) {
                        smartFilter = .favorites
                        selectedCategory = nil
                        selectedTagFilter = nil
                    }
                }

                if recentsCount > 0 {
                    sidebarButton(
                        label: "Recents", icon: "clock",
                        count: recentsCount,
                        isSelected: smartFilter == .recents
                    ) {
                        smartFilter = .recents
                        selectedCategory = nil
                        selectedTagFilter = nil
                    }
                }

                // Tags
                if !allUsedTags.isEmpty {
                    Divider()
                        .padding(.vertical, 8)

                    Text("TAGS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    ForEach(allUsedTags, id: \.self) { tag in
                        sidebarTagButton(tag: tag, isSelected: selectedTagFilter == tag) {
                            if selectedTagFilter == tag {
                                selectedTagFilter = nil
                            } else {
                                selectedTagFilter = tag
                                smartFilter = .all
                                selectedCategory = nil
                            }
                        }
                    }
                }

                // Categories
                Divider()
                    .padding(.vertical, 8)

                Text("CATEGORIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ForEach(categoriesWithCounts, id: \.category) { item in
                    sidebarButton(
                        label: item.category.rawValue,
                        icon: item.category.icon,
                        count: item.count,
                        isSelected: selectedCategory == item.category
                    ) {
                        selectedCategory = item.category
                        smartFilter = .all
                        selectedTagFilter = nil
                    }
                }
            }
            .padding(12)
        }
        .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
    }

    func sidebarTagButton(tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(TagHelper.tagColor(tag).color)
                    .frame(width: 10, height: 10)

                Text(TagHelper.tagName(tag))
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    func sidebarButton(
        label: String, icon: String, count: Int, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(UIConstants.OpacityConstants.heavy) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Chips (iPhone)

    var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(categoriesWithCounts, id: \.category) { item in
                    chipButton(label: item.category.rawValue, isSelected: selectedCategory == item.category) {
                        selectedCategory = item.category
                    }
                }
            }
        }
    }

    func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Filter Menu

    var categoryFilterMenu: some View {
        Menu {
            Button("All Categories") {
                selectedCategory = nil
            }
            Divider()
            ForEach(ResourceCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.rawValue, systemImage: category.icon)
                }
            }
        } label: {
            Label(
                selectedCategory?.rawValue ?? "All",
                systemImage: selectedCategory?.icon ?? SFSymbol.List.squareGrid
            )
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
