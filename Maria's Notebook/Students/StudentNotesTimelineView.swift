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
                let newViewModel = StudentNotesViewModel(student: student, modelContext: modelContext)
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
    @ObservedObject var viewModel: StudentNotesViewModel
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

    var filteredItems: [UnifiedNoteItem] {
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

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !debouncedSearchText.isEmpty || selectedFilter == .reportItems
    }
    
    // Group items by month and year
    private var groupedItems: [(key: String, items: [UnifiedNoteItem])] {
        let items = filteredItems
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
                    .foregroundStyle(selectedCategories.isEmpty ? .secondary : Color.accentColor)
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
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(groupedItems, id: \.key) { group in
                            // Section Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text(monthYearHeader(for: group.key))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)
                                
                                // Section Items
                                ForEach(group.items) { item in
                                    Button {
                                        if let note = resolveEditableNote(from: item) {
                                            noteBeingEdited = note
                                        }
                                    } label: {
                                        StudentNoteRowView(item: item)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if let note = resolveEditableNote(from: item) {
                                            Button {
                                                noteBeingEdited = note
                                            } label: {
                                                Label("Edit Note", systemImage: "pencil")
                                            }
                                            
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
                                        .padding(.leading, 16)
                                }
                            }
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
                        .foregroundColor(canAdd ? .accentColor : .secondary)
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
    }
    
    private var canAdd: Bool {
        !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        // FIX: Removed "guard item.source == .general" check.
        // Now we simply attempt to look up the Note by ID.
        // If it returns a valid Note object (whether attached to Work, Lesson, or General), it will be editable.
        return viewModel.note(by: item.id)
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
                        }
                    }
                }

                // Clear all button
                if !selectedCategories.isEmpty {
                    Button {
                        withAnimation {
                            selectedCategories.removeAll()
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
            Text("Showing \(filteredItems.count) of \(viewModel.items.count) notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation {
                    searchText = ""
                    debouncedSearchText = ""
                    selectedCategories.removeAll()
                    selectedFilter = .all
                }
            } label: {
                Text("Clear All")
                    .font(.caption)
                    .foregroundColor(.accentColor)
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
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: categoryIcon)
                    .font(.caption)
                Text(categoryLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? categoryColor.opacity(0.2) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? categoryColor : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? categoryColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var categoryLabel: String {
        switch category {
        case .academic: return "Academic"
        case .behavioral: return "Behavioral"
        case .social: return "Social"
        case .emotional: return "Emotional"
        case .health: return "Health"
        case .attendance: return "Attendance"
        case .general: return "General"
        }
    }

    private var categoryIcon: String {
        switch category {
        case .academic: return "book.fill"
        case .behavioral: return "hand.raised.fill"
        case .social: return "person.2.fill"
        case .emotional: return "heart.fill"
        case .health: return "cross.fill"
        case .attendance: return "calendar"
        case .general: return "note.text"
        }
    }

    private var categoryColor: Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .green
        case .general: return .gray
        }
    }
}

extension StudentNotesViewModel {
    @MainActor
    func reload() { self.reloadItems?() }
}
