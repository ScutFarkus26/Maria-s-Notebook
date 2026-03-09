// swiftlint:disable file_length
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// swiftlint:disable type_body_length
/// Main view for the Resource Library feature.
/// Displays resources organized by category with search, filter, and grid/list toggle.
struct ResourceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Resource.createdAt, order: .reverse) private var allResources: [Resource]

    @State private var searchText = ""
    @State private var selectedCategory: ResourceCategory?
    @State private var smartFilter: ResourceSmartFilter = .all
    @State private var selectedTagFilter: String?
    @State private var showingImportSheet = false
    @State private var selectedResource: Resource?
    @State private var viewMode: ResourceViewMode = .grid

    // Bulk selection
    @State private var isSelectMode = false
    @State private var selectedResourceIDs: Set<UUID> = []
    @State private var showingBulkCategoryPicker = false
    @State private var showingBulkTagPicker = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var bulkCategory: ResourceCategory = .other
    @State private var bulkTags: [String] = []

    // Rename / change category
    @State private var resourceToRename: Resource?
    @State private var renameText = ""
    @State private var resourceToRecategorize: Resource?

    // Drag-and-drop
    @State private var isDropTargeted = false

    @AppStorage("resourceLibrary.viewMode") private var viewModeRaw: String = ResourceViewMode.grid.rawValue

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    // MARK: - Filtered Data

    private var filteredResources: [Resource] {
        var result: [Resource]

        // Apply smart filter first
        switch smartFilter {
        case .all:
            result = Array(allResources)
        case .favorites:
            result = allResources.filter { $0.isFavorite }
        case .recents:
            result = allResources
                .filter { $0.lastViewedAt != nil }
                .sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
                .prefix(20)
                .map { $0 }
        }

        // Apply category filter
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }

        // Apply tag filter
        if let selectedTagFilter {
            let tagName = TagHelper.tagName(selectedTagFilter).lowercased()
            result = result.filter { resource in
                resource.tags.contains { TagHelper.tagName($0).lowercased() == tagName }
            }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.descriptionText.lowercased().contains(query) ||
                $0.categoryRaw.lowercased().contains(query) ||
                $0.tags.contains { $0.lowercased().contains(query) }
            }
        }

        return result
    }

    /// All unique tags used across resources
    private var allUsedTags: [String] {
        var seen = Set<String>()
        var uniqueTags: [String] = []
        for resource in allResources {
            for tag in resource.tags {
                let name = TagHelper.tagName(tag).lowercased()
                if !seen.contains(name) {
                    seen.insert(name)
                    uniqueTags.append(tag)
                }
            }
        }
        return uniqueTags.sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
    }

    private var favoritesCount: Int {
        allResources.filter { $0.isFavorite }.count
    }

    private var recentsCount: Int {
        min(allResources.filter { $0.lastViewedAt != nil }.count, 20)
    }

    private var groupedResources: [(category: ResourceCategory, resources: [Resource])] {
        let grouped = Dictionary(grouping: filteredResources) { $0.category }
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return (category: category, resources: resources)
        }
    }

    private var categoriesWithCounts: [(category: ResourceCategory, count: Int)] {
        let grouped = Dictionary(grouping: allResources) { $0.category }
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return (category: category, count: resources.count)
        }
    }

    // MARK: - Body

    private var selectedResources: [Resource] {
        allResources.filter { selectedResourceIDs.contains($0.id) }
    }

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
                            Label("Add Resource", systemImage: SFSymbol.Action.plus)
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
            // Drop target overlay
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
        .alert("Rename Resource", isPresented: Binding(
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
                    modelContext.safeSave()
                }
                resourceToRename = nil
            }
        }
        .sheet(item: $resourceToRecategorize) { resource in
            categoryPickerSheet(for: resource)
        }
        .confirmationDialog(
            "Delete \(selectedResourceIDs.count) Resource\(selectedResourceIDs.count == 1 ? "" : "s")?",
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

    // MARK: - Wide Layout (iPad/Mac with Sidebar)

    private var wideContent: some View {
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

    /// True if any filter beyond "All" is active
    private var hasActiveFilter: Bool {
        selectedCategory != nil || smartFilter != .all || selectedTagFilter != nil || !searchText.isEmpty
    }

    // MARK: - Compact Layout (iPhone)

    private var compactContent: some View {
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

    // MARK: - Category Sidebar

    private var categorySidebar: some View {
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
        .background(Color.primary.opacity(0.02))
    }

    private func sidebarTagButton(tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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

    private func sidebarButton(
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
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
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

    private var categoryChips: some View {
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

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Filter Menu

    private var categoryFilterMenu: some View {
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

    // MARK: - Stats Strip

    private var statsStrip: some View {
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

    private func filterPill(text: String, onDismiss: @escaping () -> Void) -> some View {
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
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
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
                .stroke(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Grouped Resources View

    private var groupedResourcesView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedResources, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    // Category header
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

    // MARK: - Resource Content (Grid or List)

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func resourceContent(_ resources: [Resource]) -> some View {
        switch viewMode {
        case .grid:
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(resources) { resource in
                    if isSelectMode {
                        selectableCard(resource: resource)
                    } else {
                        ResourceCard(resource: resource) {
                            selectedResource = resource
                        } onDelete: {
                            deleteResource(resource)
                        } onRename: {
                            renameText = resource.title
                            resourceToRename = resource
                        } onChangeCategory: {
                            resourceToRecategorize = resource
                        }
                    }
                }
            }
        case .list:
            VStack(spacing: 8) {
                ForEach(resources) { resource in
                    if isSelectMode {
                        selectableRow(resource: resource)
                    } else {
                        ResourceRow(resource: resource)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedResource = resource
                            }
                            .contextMenu {
                                Button {
                                    selectedResource = resource
                                } label: {
                                    Label("View Details", systemImage: "eye")
                                }

                                Button {
                                    renameText = resource.title
                                    resourceToRename = resource
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button {
                                    resourceToRecategorize = resource
                                } label: {
                                    Label("Change Category", systemImage: "folder")
                                }

                                Button {
                                    toggleFavorite(resource)
                                } label: {
                                    Label(
                                        resource.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: resource.isFavorite ? SFSymbol.Shape.starFill : SFSymbol.Shape.star
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteResource(resource)
                                } label: {
                                    Label("Delete", systemImage: SFSymbol.Action.trash)
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Selectable Views

    private func selectableCard(resource: Resource) -> some View {
        let isSelected = selectedResourceIDs.contains(resource.id)
        return ResourceCard(resource: resource) {
            toggleSelection(resource)
        } onDelete: {
            deleteResource(resource)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func selectableRow(resource: Resource) -> some View {
        let isSelected = selectedResourceIDs.contains(resource.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            ResourceRow(resource: resource)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(resource)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
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

            // Bulk favorite
            Button {
                bulkToggleFavorite()
            } label: {
                Label("Favorite", systemImage: SFSymbol.Shape.starFill)
            }
            .disabled(selectedResourceIDs.isEmpty)

            // Bulk categorize
            Button {
                showingBulkCategoryPicker = true
            } label: {
                Label("Categorize", systemImage: "folder")
            }
            .disabled(selectedResourceIDs.isEmpty)

            // Bulk tag
            Button {
                bulkTags = []
                showingBulkTagPicker = true
            } label: {
                Label("Tag", systemImage: "tag")
            }
            .disabled(selectedResourceIDs.isEmpty)

            // Bulk delete
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

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
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

    // MARK: - Bulk Sheets

    private var bulkCategorySheet: some View {
        NavigationStack {
            List {
                ForEach(ResourceCategory.allCases) { category in
                    Button {
                        bulkSetCategory(category)
                        showingBulkCategoryPicker = false
                    } label: {
                        Label(category.rawValue, systemImage: category.icon)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Set Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingBulkCategoryPicker = false
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }

    private var bulkTagSheet: some View {
        NavigationStack {
            Form {
                let noun = selectedResourceIDs.count == 1 ? "Resource" : "Resources"
                Section("Add Tags to \(selectedResourceIDs.count) \(noun)") {
                    TagPicker(selectedTags: $bulkTags)
                }
            }
            .navigationTitle("Add Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingBulkTagPicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        bulkAddTags(bulkTags)
                        showingBulkTagPicker = false
                    }
                    .disabled(bulkTags.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func categoryPickerSheet(for resource: Resource) -> some View {
        NavigationStack {
            List {
                ForEach(ResourceCategory.allCases) { category in
                    Button {
                        resource.category = category
                        resource.modifiedAt = Date()
                        modelContext.safeSave()
                        resourceToRecategorize = nil
                    } label: {
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if resource.category == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resourceToRecategorize = nil
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }

    private var gridColumns: [GridItem] {
        #if os(iOS)
        if isCompact {
            return [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]
        }
        #endif
        return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]
    }

    // MARK: - Empty States

    private var emptyState: some View {
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

    private var noResultsState: some View {
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

    // MARK: - Actions

    private func deleteResource(_ resource: Resource) {
        let repo = ResourceRepository(context: modelContext)
        repo.deleteResource(resource)
        modelContext.safeSave()
    }

    private func toggleFavorite(_ resource: Resource) {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        modelContext.safeSave()
    }

    // MARK: - Selection

    private func toggleSelection(_ resource: Resource) {
        if selectedResourceIDs.contains(resource.id) {
            selectedResourceIDs.remove(resource.id)
        } else {
            selectedResourceIDs.insert(resource.id)
        }
    }

    private func exitSelectMode() {
        isSelectMode = false
        selectedResourceIDs.removeAll()
    }

    // MARK: - Bulk Actions

    private func bulkToggleFavorite() {
        let resources = selectedResources
        let allFavorited = resources.allSatisfy { $0.isFavorite }
        for resource in resources {
            resource.isFavorite = !allFavorited
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    private func bulkSetCategory(_ category: ResourceCategory) {
        for resource in selectedResources {
            resource.category = category
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    private func bulkAddTags(_ tags: [String]) {
        for resource in selectedResources {
            for tag in tags {
                let tagName = TagHelper.tagName(tag).lowercased()
                if !resource.tags.contains(where: { TagHelper.tagName($0).lowercased() == tagName }) {
                    resource.tags.append(tag)
                }
            }
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    private func bulkDelete() {
        let repo = ResourceRepository(context: modelContext)
        for resource in selectedResources {
            repo.deleteResource(resource)
        }
        modelContext.safeSave()
        exitSelectMode()
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didImport = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else { return }

                // Copy file to a temp location before the callback closes it
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                try? FileManager.default.copyItem(at: url, to: tempURL)

                Task { @MainActor in
                    importDroppedPDF(from: tempURL)
                }
            }
            didImport = true
        }
        return didImport
    }

    @MainActor
    private func importDroppedPDF(from tempURL: URL) {
        let stem = tempURL.deletingPathExtension().lastPathComponent
        let title = stem.isEmpty ? "Imported Resource" : stem

        do {
            let resourceID = UUID()
            let (destURL, relativePath) = try ResourceFileStorage.importFile(
                from: tempURL,
                resourceID: resourceID,
                title: title,
                category: .other
            )
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destURL.path)
            let fileSize = (fileAttributes[.size] as? Int64) ?? 0
            let bookmark = try ResourceFileStorage.makeBookmark(for: destURL)
            let thumbnail = ResourceThumbnailGenerator.generateThumbnail(from: destURL)

            let repo = ResourceRepository(context: modelContext)
            repo.createResource(
                title: title,
                category: .other,
                fileBookmark: bookmark,
                fileRelativePath: relativePath,
                fileSizeBytes: fileSize,
                thumbnailData: thumbnail
            )
            modelContext.safeSave()
        } catch {
            // Silently fail — resource wasn't imported
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
}

// MARK: - View Mode

enum ResourceViewMode: String {
    case grid
    case list
}

// MARK: - Smart Filter

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
// swiftlint:enable type_body_length

#Preview {
    ResourceLibraryView()
        .previewEnvironment()
}
