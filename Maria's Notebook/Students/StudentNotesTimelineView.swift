// swiftlint:disable file_length
//
//  StudentNotesTimelineView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/27/25.
//

import OSLog
import SwiftUI
import CoreData

private let logger = Logger.students

extension StudentNotesViewModel {
    // Hooks that the real view model can set; safe no-ops by default
    var itemsNoteLookup: ((UUID) -> CDNote?)? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.lookup) as? (UUID) -> CDNote? }
        set { objc_setAssociatedObject(self, &AssociatedKeys.lookup, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var reloadItems: (() -> Void)? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.reload) as? () -> Void }
        set { objc_setAssociatedObject(self, &AssociatedKeys.reload, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private struct AssociatedKeys {
        nonisolated(unsafe) static var lookup: UInt8 = 0
        nonisolated(unsafe) static var reload: UInt8 = 0
    }
}

struct StudentNotesTimelineView: View {
    let student: CDStudent
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @State private var viewModel: StudentNotesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                StudentNotesTimelineList(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                let newViewModel = StudentNotesViewModel(
                    student: student,
                    viewContext: viewContext,
                    saveCoordinator: saveCoordinator
                )
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
// swiftlint:disable:next type_body_length
struct StudentNotesTimelineList: View {
    @Bindable var viewModel: StudentNotesViewModel
    @Environment(\.calendar) var calendar

    enum NoteFilter: String, CaseIterable, Identifiable {
        case all = "All Notes"
        case reportItems = "Report Items Only"
        case followUp = "Needs Follow-Up"

        var id: String { rawValue }
    }

    @State var selectedFilter: NoteFilter = .all
    @State private var newNoteText: String = ""
    @State private var noteBeingEdited: CDNote?

    // Search and tag filtering state
    @State var searchText: String = ""
    @State var debouncedSearchText: String = ""
    @State var selectedFilterTags: Set<String> = []
    @State private var showingTagFilter: Bool = false

    // Batch selection state
    @State var isSelecting: Bool = false
    @State var selectedNoteIDs: Set<UUID> = []
    @State private var showingDeleteConfirmation: Bool = false

    // Pagination state
    @State var displayedCount: Int = 30
    let pageSize: Int = 30

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
                                adaptiveWithAnimation {
                                    selectedFilter = filter
                                    resetPagination()
                                }
                            }
                        }
                    }
                }

                // Tag filter button
                Button {
                    showingTagFilter.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        if !selectedFilterTags.isEmpty {
                            Text("\(selectedFilterTags.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(selectedFilterTags.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter by tag")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.background)

            // Tag filter chips (collapsible)
            if showingTagFilter {
                tagFilterSection
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
            
            // Quick CDNote Bar
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
                    adaptiveWithAnimation {
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

                        // Add tags from common tags
                        Menu {
                            ForEach(TagHelper.commonTags, id: \.0) { name, color in
                                Button {
                                    batchAddTag(TagHelper.createTag(name: name, color: color))
                                } label: {
                                    Label(name, systemImage: "tag")
                                }
                            }
                        } label: {
                            Label("Add Tag", systemImage: "tag.fill")
                        }

                        // Remove tags used by selected notes
                        let selectedItems = viewModel.items.filter { selectedNoteIDs.contains($0.id) }
                        let usedTags = Set(selectedItems.flatMap { $0.tags })
                        if !usedTags.isEmpty {
                            Menu {
                                ForEach(
                                    usedTags.sorted { TagHelper.tagName($0) < TagHelper.tagName($1) },
                                    id: \.self
                                ) { tag in
                                    Button {
                                        batchRemoveTag(tag)
                                    } label: {
                                        Label(TagHelper.tagName(tag), systemImage: "minus.circle")
                                    }
                                }
                            } label: {
                                Label("Remove Tag", systemImage: "tag.slash")
                            }
                        }

                        Divider()

                        Button {
                            batchToggleFollowUp()
                        } label: {
                            Label("Toggle Follow-Up", systemImage: "flag")
                        }

                        Button {
                            batchToggleReportFlag()
                        } label: {
                            Label("Toggle Report Flag", systemImage: "doc.text")
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

    private var canAdd: Bool {
        !newNoteText.trimmed().isEmpty
    }
    
    private func addNote() {
        guard canAdd else { return }
        adaptiveWithAnimation {
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
        case .followUp:
            return "No notes need follow-up."
        }
    }

    @MainActor
    private func resolveEditableNote(from item: UnifiedNoteItem) -> CDNote? {
        // Attempt to look up the CDNote by ID.
        // If it returns a valid CDNote object (whether attached to Work, CDLesson, or General), it will be editable.
        return viewModel.note(by: item.id)
    }

    // MARK: - CDNote Row

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

            // CDNote content
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
                    Label("Edit CDNote", systemImage: "pencil")
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
                    Label("Delete CDNote", systemImage: "trash")
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
            .background(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
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
    private func togglePin(_ note: CDNote) {
        adaptiveWithAnimation {
            note.isPinned.toggle()
            note.updatedAt = Date()
            do {
                try viewModel.viewContext.save()
            } catch {
                logger.warning("Failed to save pin toggle: \(error)")
            }
            viewModel.fetchAllNotes()
        }
    }

}

extension StudentNotesViewModel {
    @MainActor
    func reload() { self.reloadItems?() }
}
