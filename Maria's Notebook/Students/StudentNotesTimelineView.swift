//
//  StudentNotesTimelineView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/27/25.
//

import SwiftUI
import SwiftData

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
                viewModel = StudentNotesViewModel(student: student, modelContext: modelContext)
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

    var filteredItems: [UnifiedNoteItem] {
        let items = viewModel.items
        switch selectedFilter {
        case .all:
            return items
        case .reportItems:
            return items.filter { $0.includeInReport }
        }
    }
    
    // Group items by month and year
    private var groupedItems: [(key: String, items: [UnifiedNoteItem])] {
        let items = filteredItems
        let grouped = Dictionary(grouping: items) { item -> String in
            monthYearKey(for: item.date)
        }
        .mapValues { items in
            items.sorted { $0.date > $1.date } // Sort items within each group (newest first)
        }
        
        // Sort groups by date (newest first)
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            // Parse the keys to compare dates properly
            // Format is "YYYY-MM" so we can sort as strings
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
        // Key format is "YYYY-MM"
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Filter Pills
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
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            // FIX: Use standard SwiftUI material background instead of UIColor
            .background(.background)
            
            Divider()

            // List Content
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
                List {
                    ForEach(groupedItems, id: \.key) { group in
                        Section {
                            ForEach(group.items) { item in
                                StudentNoteRowView(item: item)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.visible)
                            }
                            .onDelete { offsets in
                                deleteItems(at: offsets, in: group.items)
                            }
                        } header: {
                            Text(monthYearHeader(for: group.key))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
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
        switch selectedFilter {
        case .all:
            return "This student has no notes recorded yet."
        case .reportItems:
            return "No notes are flagged for reports."
        }
    }

    private func deleteItems(at offsets: IndexSet, in items: [UnifiedNoteItem]) {
        let itemsToDelete = offsets.map { items[$0] }
        
        for item in itemsToDelete {
            withAnimation {
                viewModel.delete(item: item)
            }
        }
    }
}
