//
//  StudentNotesTimelineView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/27/25.
//

import SwiftUI
import SwiftData

extension StudentNotesViewModel {
    // Hooks that the real view model can set; safe no-ops by default
    var itemsNoteLookup: ((UUID) -> Note?)? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.lookup) as? (UUID) -> Note? }
        set { objc_setAssociatedObject(self, &AssociatedKeys.lookup, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var reloadItems: (() -> Void)? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.reload) as? () -> Void }
        set { objc_setAssociatedObject(self, &AssociatedKeys.reload, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private struct AssociatedKeys {
        static var lookup: UInt8 = 0
        static var reload: UInt8 = 0
    }
}

struct StudentNotesTimelineView: View {
    let student: Student
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @State private var viewModel: StudentNotesViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                StudentNotesTimelineList(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                let newViewModel = StudentNotesViewModel(student: student, modelContext: modelContext, saveCoordinator: saveCoordinator)
                // Set up the note lookup function
                newViewModel.itemsNoteLookup = { id in
                    newViewModel.note(by: id)
                }
                // Set up the reload function
                newViewModel.reloadItems = {
                    newViewModel.fetchAllNotes()
                }
                viewModel = newViewModel
            }
        }
    }
}

// MARK: - Internal List View
private struct StudentNotesTimelineList: View {
    @Bindable var viewModel: StudentNotesViewModel
    @Environment(\.calendar) private var calendar

    enum NoteFilter: String, CaseIterable, Identifiable {
        case all = "All Notes"
        case reportItems = "Report Items Only"

        var id: String { rawValue }
    }

    @State private var selectedFilter: NoteFilter = .all
    @State private var newNoteText: String = ""
    @State private var noteBeingEdited: Note? = nil

    // Search and category filtering state
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var selectedCategories: Set<NoteCategory> = []
    @State private var showingCategoryFilter: Bool = false

    // Batch selection state
    @State private var isSelecting: Bool = false
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var showingDeleteConfirmation: Bool = false

    // All filtered items (for counting)
    var allFilteredItems: [UnifiedNoteItem] {
        var items = viewModel.items

        // Apply report filter
        if selectedFilter == .reportItems {
            items = items.filter { $0.includeInReport }
        }

        // Apply category filter
        if !selectedCategories.isEmpty {
            items = items.filter { selectedCategories.contains($0.category) }
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

    // Paginated filtered items for display
    var filteredItems: [UnifiedNoteItem] {
        Array(allFilteredItems.prefix(displayedCount))
    }

    // Pagination state
    @State private var displayedCount: Int = 30
    private let pageSize: Int = 30

    var hasMoreItems: Bool {
        displayedCount < allFilteredItems.count
    }

    private func loadMoreItems() {
        let newCount = min(displayedCount + pageSize, allFilteredItems.count)
        withAnimation {
            displayedCount = newCount
        }
    }

    private func resetPagination() {
        displayedCount = pageSize
    }

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !debouncedSearchText.isEmpty || selectedFilter == .reportItems
    }

    // Separate pinned and unpinned items
    private var pinnedItems: [UnifiedNoteItem] {
        filteredItems.filter { $0.isPinned }
    }

    private var unpinnedItems: [UnifiedNoteItem] {
        filteredItems.filter { !$0.isPinned }
    }

    // Group unpinned items by month and year
    private var groupedItems: [(key: String, items: [UnifiedNoteItem])] {
        let items = unpinnedItems
        let grouped = items.grouped { monthYearKey(for: $0.date) }
        .mapValues { items in
            items.sorted { $0.date > $1.date } // Sort items within each group (newest first)
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
    
    private func monthYearKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
    
    private func monthYearHeader(for key: String) -> String {
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

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            DebouncedSearchField("Search notes...", text: $searchText) { debounced in
                debouncedSearchText = debounced
                resetPagination()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Header: Filter Pills and Category Button
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(NoteFilter.allCases) { filter in
                            PillButton(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation {
                                    selectedFilter = filter
                                    resetPagination()
                                }
                            }
                        }
                    }
                }

                // Category filter button
                Button {
                    showingCategoryFilter.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        if !selectedCategories.isEmpty {
                            Text("\(selectedCategories.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(selectedCategories.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter by category")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.background)

            // Category filter chips (collapsible)
            if showingCategoryFilter {
                categoryFilterSection
            }

            // Active filters summary
            if hasActiveFilters {
                activeFiltersSummary
            }

            Divider()

            // List Content - Using ScrollView + LazyVStack to avoid nested List issues
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    label: {
                        Label("No Notes Found", systemImage: "note.text")
                    },
                    description: {
                        Text(emptyStateMessage)
                    }
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Pinned Notes Section
                        if !pinnedItems.isEmpty {
                            Section {
                                ForEach(pinnedItems) { item in
                                    noteRow(for: item)
                                }
                            } header: {
                                pinnedSectionHeader
                            }
                        }

                        // Monthly grouped sections
                        ForEach(groupedItems, id: \.key) { group in
                            Section {
                                ForEach(group.items) { item in
                                    noteRow(for: item)
                                }
                            } header: {
                                Text(monthYearHeader(for: group.key))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.background)
                            }
                        }

                        // Load More trigger
                        if hasMoreItems {
                            loadMoreButton
                        }
                    }
                }
            }
            
            // Quick Note Bar
            Divider()
            HStack(spacing: 10) {
                TextField("Add a note...", text: $newNoteText)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: addNote) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)
                }
                .disabled(!canAdd)
            }
            .padding()
            .background(.bar)
        }
        .sheet(item: $noteBeingEdited) { note in
            NoteEditSheet(note: note) {
                // Reload the view model after edits to reflect changes
                viewModel.reload()
            }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            .presentationSizingFitted()
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
        .toolbar {
            // Selection mode toggle
            ToolbarItem(placement: .automatic) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation {
                        if isSelecting {
                            selectedNoteIDs.removeAll()
                        }
                        isSelecting.toggle()
                    }
                }
            }

            // Batch actions menu (only when selecting and items are selected)
            if isSelecting && !selectedNoteIDs.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete (\(selectedNoteIDs.count))", systemImage: "trash")
                        }

                        Divider()

                        Menu {
                            ForEach(NoteCategory.allCases, id: \.self) { category in
                                Button {
                                    batchUpdateCategory(to: category)
                                } label: {
                                    Label(NoteCategoryHelpers.label(for: category), systemImage: NoteCategoryHelpers.icon(for: category))
                                }
                            }
                        } label: {
                            Label("Change Category", systemImage: "tag")
                        }

                        Button {
                            batchToggleReportFlag()
                        } label: {
                            Label("Toggle Report Flag", systemImage: "flag")
                        }

                        Button {
                            batchTogglePin()
                        } label: {
                            Label("Toggle Pin", systemImage: "pin")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedNoteIDs.count) note\(selectedNoteIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                batchDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Batch Operations

    private func performBatchAction(_ action: (Set<UUID>) -> Void) {
        withAnimation {
            action(selectedNoteIDs)
            selectedNoteIDs.removeAll()
            isSelecting = false
        }
    }

    private func batchDelete() {
        performBatchAction(viewModel.batchDelete(ids:))
    }

    private func batchUpdateCategory(to category: NoteCategory) {
        performBatchAction { viewModel.batchUpdateCategory(category, for: $0) }
    }

    private func batchToggleReportFlag() {
        performBatchAction(viewModel.batchToggleReportFlag(for:))
    }

    private func batchTogglePin() {
        performBatchAction(viewModel.batchTogglePin(for:))
    }

    
    private var canAdd: Bool {
        !newNoteText.trimmed().isEmpty
    }
    
    private func addNote() {
        guard canAdd else { return }
        withAnimation {
            viewModel.addGeneralNote(body: newNoteText)
            newNoteText = ""
        }
    }
    
    private var emptyStateMessage: String {
        if hasActiveFilters {
            return "No notes match your current filters."
        }
        switch selectedFilter {
        case .all:
            return "This student has no notes recorded yet."
        case .reportItems:
            return "No notes are flagged for reports."
        }
    }

    @MainActor
    private func resolveEditableNote(from item: UnifiedNoteItem) -> Note? {
        // Attempt to look up the Note by ID.
        // If it returns a valid Note object (whether attached to Work, Lesson, or General), it will be editable.
        return viewModel.note(by: item.id)
    }

    // MARK: - Note Row

    @ViewBuilder
    private func noteRow(for item: UnifiedNoteItem) -> some View {
        HStack(spacing: 12) {
            // Selection checkbox (only in selection mode)
            if isSelecting {
                Button {
                    toggleSelection(for: item.id)
                } label: {
                    Image(systemName: selectedNoteIDs.contains(item.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedNoteIDs.contains(item.id)
                                         ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            // Note content
            Button {
                if isSelecting {
                    toggleSelection(for: item.id)
                } else if let note = resolveEditableNote(from: item) {
                    noteBeingEdited = note
                }
            } label: {
                StudentNoteRowView(item: item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            if !isSelecting, let note = resolveEditableNote(from: item) {
                Button {
                    noteBeingEdited = note
                } label: {
                    Label("Edit Note", systemImage: "pencil")
                }

                Button {
                    togglePin(note)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin to Top",
                          systemImage: note.isPinned ? "pin.slash" : "pin")
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.delete(item: item)
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)

        Divider()
            .padding(.leading, isSelecting ? 52 : 16)
    }

    private func toggleSelection(for id: UUID) {
        if selectedNoteIDs.contains(id) {
            selectedNoteIDs.remove(id)
        } else {
            selectedNoteIDs.insert(id)
        }
    }

    // MARK: - Load More Button

    private var loadMoreButton: some View {
        Button {
            loadMoreItems()
        } label: {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("Load More")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(allFilteredItems.count - displayedCount) more notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Pinned Section Header

    private var pinnedSectionHeader: some View {
        SectionHeaderView(title: "Pinned", icon: "pin.fill", iconColor: .orange)
    }

    // MARK: - Pin/Unpin

    @MainActor
    private func togglePin(_ note: Note) {
        withAnimation {
            note.isPinned.toggle()
            note.updatedAt = Date()
            do {
                try viewModel.modelContext.save()
            } catch {
                print("⚠️ [togglePin] Failed to save: \(error)")
            }
            viewModel.fetchAllNotes()
        }
    }

    // MARK: - Category Filter Section

    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NoteCategory.allCases, id: \.self) { category in
                    CategoryFilterChip(
                        category: category,
                        isSelected: selectedCategories.contains(category)
                    ) {
                        withAnimation {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                            resetPagination()
                        }
                    }
                }

                // Clear all button
                if !selectedCategories.isEmpty {
                    Button {
                        withAnimation {
                            selectedCategories.removeAll()
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
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Active Filters Summary

    private var activeFiltersSummary: some View {
        HStack {
            Text("Showing \(allFilteredItems.count) of \(viewModel.items.count) notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation {
                    searchText = ""
                    debouncedSearchText = ""
                    selectedCategories.removeAll()
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
        .background(Color.accentColor.opacity(0.08))
    }
}

// MARK: - Category Filter Chip

private struct CategoryFilterChip: View {
    let category: NoteCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        StudentFilterChip(
            label: NoteCategoryHelpers.label(for: category),
            icon: NoteCategoryHelpers.icon(for: category),
            color: NoteCategoryHelpers.color(for: category),
            isSelected: isSelected,
            action: action
        )
    }
}

extension StudentNotesViewModel {
    @MainActor
    func reload() { self.reloadItems?() }
}
