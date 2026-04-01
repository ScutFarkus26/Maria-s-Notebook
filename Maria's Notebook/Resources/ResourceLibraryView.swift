// ResourceLibraryView.swift
// Main view for the CDResource Library feature.
// Displays resources organized by category with search, filter, and grid/list toggle.
//
// Extensions:
// - ResourceLibraryView+Sidebar.swift   (categorySidebar, chips, category menu)
// - ResourceLibraryView+Layout.swift    (wideContent, compactContent, searchBar, statsStrip, etc.)
// - ResourceLibraryView+Content.swift   (resourceContent, selectableCard/Row)
// - ResourceLibraryView+Sheets.swift    (bulk category/tag pickers, categoryPickerSheet)
// - ResourceLibraryView+Actions.swift   (delete, favorite, selection, bulk ops, drag-and-drop)

import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Main view for the CDResource Library feature.
/// Displays resources organized by category with search, filter, and grid/list toggle.
struct ResourceLibraryView: View {
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDResource.createdAt, ascending: false)]) var allResources: FetchedResults<CDResource>

    @State var searchText = ""
    @State var selectedCategory: ResourceCategory?
    @State var smartFilter: ResourceSmartFilter = .all
    @State var selectedTagFilter: String?
    @State var showingImportSheet = false
    @State var selectedResource: CDResource?
    @State var viewMode: ResourceViewMode = .grid

    // Bulk selection
    @State var isSelectMode = false
    @State var selectedResourceIDs: Set<UUID> = []
    @State var showingBulkCategoryPicker = false
    @State var showingBulkTagPicker = false
    @State var showingBulkDeleteConfirmation = false
    @State var bulkCategory: ResourceCategory = .other
    @State var bulkTags: [String] = []

    // Rename / change category
    @State var resourceToRename: CDResource?
    @State var renameText = ""
    @State var resourceToRecategorize: CDResource?

    // Drag-and-drop
    @State var isDropTargeted = false

    @AppStorage("resourceLibrary.viewMode") var viewModeRaw: String = ResourceViewMode.grid.rawValue

    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    // MARK: - Filtered Data

    var filteredResources: [CDResource] {
        var result: [CDResource]

        // Apply smart filter first
        switch smartFilter {
        case .all:
            result = Array(allResources)
        case .favorites:
            result = allResources.filter(\.isFavorite)
        case .recents:
            result = Array(allResources
                .filter { $0.lastViewedAt != nil }
                .sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
                .prefix(20))
        }

        // Apply category filter
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }

        // Apply tag filter
        if let selectedTagFilter {
            let tagName = TagHelper.tagName(selectedTagFilter).lowercased()
            result = result.filter { resource in
                resource.tagsArray.contains { TagHelper.tagName($0).lowercased() == tagName }
            }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.descriptionText.lowercased().contains(query) ||
                $0.categoryRaw.lowercased().contains(query) ||
                $0.tagsArray.contains { $0.lowercased().contains(query) }
            }
        }

        return result
    }

    /// All unique tags used across resources
    var allUsedTags: [String] {
        var seen = Set<String>()
        var uniqueTags: [String] = []
        for resource in allResources {
            for tag in resource.tagsArray {
                let name = TagHelper.tagName(tag).lowercased()
                if !seen.contains(name) {
                    seen.insert(name)
                    uniqueTags.append(tag)
                }
            }
        }
        return uniqueTags.sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
    }

    var favoritesCount: Int {
        allResources.filter(\.isFavorite).count
    }

    var recentsCount: Int {
        min(allResources.filter { $0.lastViewedAt != nil }.count, 20)
    }

    var groupedResources: [(category: ResourceCategory, resources: [CDResource])] {
        let grouped = Dictionary(grouping: filteredResources) { $0.category }
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return (category: category, resources: resources)
        }
    }

    var categoriesWithCounts: [(category: ResourceCategory, count: Int)] {
        let grouped = Dictionary(grouping: allResources) { $0.category }
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return (category: category, count: resources.count)
        }
    }

    var selectedResources: [CDResource] {
        allResources.filter { resource in
            guard let resourceID = resource.id else { return false }
            return selectedResourceIDs.contains(resourceID)
        }
    }

    /// True if any filter beyond "All" is active
    var hasActiveFilter: Bool {
        selectedCategory != nil || smartFilter != .all || selectedTagFilter != nil || !searchText.isEmpty
    }

    var gridColumns: [GridItem] {
        #if os(iOS)
        if isCompact {
            return [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]
        }
        #endif
        return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Resources") {
                HStack(spacing: 12) {
                    if isSelectMode {
                        // Bulk mode controls
                        Text("\(selectedResourceIDs.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Done") {
                            exitSelectMode()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        // View mode toggle
                        Picker("View", selection: $viewMode) {
                            Image(systemName: SFSymbol.List.squareGrid).tag(ResourceViewMode.grid)
                            Image(systemName: SFSymbol.List.list).tag(ResourceViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)

                        // Category filter (shown on compact / when no sidebar)
                        if isCompact {
                            categoryFilterMenu
                        }

                        // Select button
                        if !allResources.isEmpty {
                            Button {
                                isSelectMode = true
                            } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                            .controlSize(.small)
                        }

                        // Add button
                        Button {
                            showingImportSheet = true
                        } label: {
                            Label("Add CDResource", systemImage: SFSymbol.Action.plus)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            // Bulk action bar
            if isSelectMode {
                bulkActionBar
            }

            Divider()

            if isCompact {
                compactContent
            } else {
                wideContent
            }
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            viewMode = ResourceViewMode(rawValue: viewModeRaw) ?? .grid
        }
        .onChange(of: viewMode) { _, newValue in
            viewModeRaw = newValue.rawValue
        }
        .sheet(isPresented: $showingImportSheet) {
            ResourceImportSheet()
        }
        .sheet(item: $selectedResource) { resource in
            ResourceDetailView(resource: resource)
        }
        .sheet(isPresented: $showingBulkCategoryPicker) {
            bulkCategorySheet
        }
        .sheet(isPresented: $showingBulkTagPicker) {
            bulkTagSheet
        }
        .alert("Rename CDResource", isPresented: Binding(
            get: { resourceToRename != nil },
            set: { if !$0 { resourceToRename = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {
                resourceToRename = nil
            }
            Button("Save") {
                if let resource = resourceToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    resource.title = renameText.trimmingCharacters(in: .whitespaces)
                    resource.modifiedAt = Date()
                    viewContext.safeSave()
                }
                resourceToRename = nil
            }
        }
        .sheet(item: $resourceToRecategorize) { resource in
            categoryPickerSheet(for: resource)
        }
        .confirmationDialog(
            "Delete \(selectedResourceIDs.count) CDResource\(selectedResourceIDs.count == 1 ? "" : "s")?",
            isPresented: $showingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                bulkDelete()
            }
        } message: {
            Text("This will permanently delete the selected resources and their files.")
        }
    }
}

// MARK: - Supporting Types

enum ResourceViewMode: String {
    case grid
    case list
}

enum ResourceSmartFilter: String {
    case all
    case favorites
    case recents

    var displayName: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        }
    }
}

#Preview {
    ResourceLibraryView()
        .previewEnvironment()
}
