// ResourceLibraryView+Layout.swift
// Layout containers, search bar, stats strip, bulk action bar, and overlay views.

import SwiftUI

extension ResourceLibraryView {

    // MARK: - Wide Layout (iPad/Mac with Sidebar)

    var wideContent: some View {
        HStack(spacing: 0) {
            // Category sidebar
            categorySidebar
                .frame(width: 220)

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchBar
                    statsStrip

                    if allResources.isEmpty {
                        emptyState
                    } else if filteredResources.isEmpty {
                        noResultsState
                    } else if hasActiveFilter {
                        resourceContent(filteredResources)
                    } else {
                        groupedResourcesView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Compact Layout (iPhone)

    var compactContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                searchBar

                // Horizontal category chips
                if !categoriesWithCounts.isEmpty {
                    categoryChips
                }

                if allResources.isEmpty {
                    emptyState
                } else if filteredResources.isEmpty {
                    noResultsState
                } else if hasActiveFilter {
                    resourceContent(filteredResources)
                } else {
                    groupedResourcesView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Search Bar

    var searchBar: some View {
        HStack {
            Image(systemName: SFSymbol.Search.magnifyingglass)
                .foregroundStyle(.secondary)

            TextField("Search resources...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: SFSymbol.Action.xmarkCircleFill)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
        )
    }

    // MARK: - Stats Strip

    var statsStrip: some View {
        HStack(spacing: 8) {
            Text("\(filteredResources.count) resource\(filteredResources.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if smartFilter != .all {
                filterPill(text: smartFilter.displayName) {
                    smartFilter = .all
                }
            }

            if let selectedCategory {
                filterPill(text: selectedCategory.rawValue) {
                    self.selectedCategory = nil
                }
            }

            if let selectedTagFilter {
                filterPill(text: TagHelper.tagName(selectedTagFilter)) {
                    self.selectedTagFilter = nil
                }
            }

            Spacer()
        }
    }

    func filterPill(text: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Button(action: onDismiss) {
                Image(systemName: SFSymbol.Action.xmarkCircleFill)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent)))
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Bulk Action Bar

    var bulkActionBar: some View {
        HStack(spacing: 16) {
            Button {
                if selectedResourceIDs.count == filteredResources.count {
                    selectedResourceIDs.removeAll()
                } else {
                    selectedResourceIDs = Set(filteredResources.map(\.id))
                }
            } label: {
                Text(selectedResourceIDs.count == filteredResources.count ? "Deselect All" : "Select All")
                    .font(.caption.weight(.medium))
            }

            Spacer()

            Button {
                bulkToggleFavorite()
            } label: {
                Label("Favorite", systemImage: SFSymbol.Shape.starFill)
            }
            .disabled(selectedResourceIDs.isEmpty)

            Button {
                showingBulkCategoryPicker = true
            } label: {
                Label("Categorize", systemImage: "folder")
            }
            .disabled(selectedResourceIDs.isEmpty)

            Button {
                bulkTags = []
                showingBulkTagPicker = true
            } label: {
                Label("Tag", systemImage: "tag")
            }
            .disabled(selectedResourceIDs.isEmpty)

            Button(role: .destructive) {
                showingBulkDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }
            .disabled(selectedResourceIDs.isEmpty)
        }
        .font(.caption)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Drop Overlay

    var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                Text("Drop PDF files to import")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(24)
        .allowsHitTesting(false)
    }

    // MARK: - Grouped Resources View

    var groupedResourcesView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedResources, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: group.category.icon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(group.category.rawValue)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.resources.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    resourceContent(group.resources)
                }
            }
        }
    }

    // MARK: - Empty States

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Resources Yet")
                .font(.title2.weight(.semibold))

            Text("Add PDF documents to build your classroom resource library.\n" +
                 "Organize writing papers, templates, guides, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingImportSheet = true
            } label: {
                Label("Add First Resource", systemImage: SFSymbol.Action.plus)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: SFSymbol.Search.magnifyingglass)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No resources found")
                .font(.headline)

            Text("Try adjusting your search or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
