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
    
    enum NoteFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case general = "General"
        case work = "Work"
        case lessons = "Lessons"
        
        var id: String { rawValue }
    }
    
    @State private var selectedFilter: NoteFilter = .all
    @State private var newNoteText: String = ""

    var filteredItems: [UnifiedNoteItem] {
        switch selectedFilter {
        case .all:
            return viewModel.items
        case .general:
            return viewModel.items.filter { $0.source == .general }
        case .work:
            return viewModel.items.filter { $0.source == .work }
        case .lessons:
            return viewModel.items.filter { $0.source == .lesson }
        }
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
                    ForEach(filteredItems) { item in
                        StudentNoteRowView(item: item)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.visible)
                    }
                    .onDelete(perform: deleteItems)
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
        default:
            return "No notes found for the '\(selectedFilter.rawValue)' filter."
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        // Map the indices from the filtered list back to the actual items
        let itemsToDelete = offsets.map { filteredItems[$0] }
        
        for item in itemsToDelete {
            withAnimation {
                viewModel.delete(item: item)
            }
        }
    }
}
