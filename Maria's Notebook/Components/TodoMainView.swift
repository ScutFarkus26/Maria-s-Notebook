// TodoMainView.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

/// Main todo view with elegant layout inspired by Things and Bear
struct TodoMainView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) var allTodos: [TodoItem]

    @State var selectedFilter: TodoListFilter? = .inbox
    @State var searchText = ""
    @State var selectedTodo: TodoItem?
    @State private var isShowingNewTodo = false
    @State private var isShowingTemplates = false
    @State private var isShowingExport = false
    @State private var showingSortOptions = false
    @State var sortBy: TodoSortOption = .dueDate
    @State var isSelectMode = false
    @State var selectedTodoIDs: Set<UUID> = []
    @State var selectedTag: String?
    @State var expandedTagGroups: Set<String> = [TodoTagHelper.studentTagParent]
    @State var tagOrder: [String] = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.todoTagOrder) ?? []
    @State var selectedFolder: String?
    @State var isShowingNewFolder = false
    @State var newFolderName = ""
    @State private var draggingTag: String?

    // PERF: Cached computed results to avoid recomputing on every body evaluation.
    // Refreshed via .onChange handlers when source data changes.
    @State var cachedAllUsedTags: [String] = []
    @State var cachedFilterCounts: [TodoListFilter: Int] = [:]
    @State var cachedTagCounts: [String: Int] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                .frame(width: 220)

            Divider()

            if let selectedTodo = selectedTodo {
                VStack(spacing: 0) {
                    HStack {
                        Text("Edit Todo")
                            .font(AppTheme.ScaledFont.body.weight(.semibold))
                        Spacer()
                        Button("Done") {
                            self.selectedTodo = nil
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    EditTodoForm(todo: selectedTodo)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                todoListContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    adaptiveWithAnimation(.snappy(duration: 0.2)) {
                        isSelectMode.toggle()
                        if !isSelectMode { selectedTodoIDs.removeAll() }
                    }
                } label: {
                    Label(
                        isSelectMode ? "Done" : "Select",
                        systemImage: isSelectMode ? "checkmark.circle" : "checklist.unchecked"
                    )
                }

                Menu {
                    ForEach(TodoSortOption.allCases) { option in
                        Button {
                            sortBy = option
                        } label: {
                            Label(option.title, systemImage: sortBy == option ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    Button {
                        isShowingTemplates = true
                    } label: {
                        Label("Templates", systemImage: "doc.on.doc")
                    }

                    Button {
                        isShowingExport = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        deleteCompletedTodos()
                    } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                    .disabled(allTodos.filter(\.isCompleted).isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }

                Button {
                    isShowingNewTodo = true
                } label: {
                    Label("New Todo", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $isShowingNewTodo) {
            newTodoSheet
        }
        .sheet(isPresented: $isShowingTemplates) {
            TodoTemplatesView()
        }
        .sheet(isPresented: $isShowingExport) {
            TodoExportView(todos: filteredTodos)
        }
        .sheet(isPresented: $isShowingNewFolder) {
            newFolderSheet
        }
        .onAppear { refreshTagCaches() }
        .onChange(of: allTodos.count) { _, _ in refreshTagCaches() }
    }

    // PERF: Compute tag data and filter/tag counts in a single pass over allTodos.
    // Previously each was a separate computed property scanning allTodos independently.
    func refreshTagCaches() {
        // Build allUsedTags
        var tagSet = Set<String>()
        // Build filter counts and tag counts in the same pass
        var filterCounts: [TodoListFilter: Int] = [:]
        var tagCounts: [String: Int] = [:]

        for todo in allTodos {
            // Count filters
            for filter in TodoListFilter.allCases where filter != .all {
                if filter.matches(todo) {
                    filterCounts[filter, default: 0] += 1
                }
            }
            // Collect tags and count per-tag
            for tag in todo.tags {
                tagSet.insert(tag)
                tagCounts[tag, default: 0] += 1
            }
        }

        cachedAllUsedTags = tagSet.sorted {
            TodoTagHelper.tagName($0)
                .localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
        cachedFilterCounts = filterCounts
        cachedTagCounts = tagCounts
    }

    // MARK: - Helper Functions

    private func deleteCompletedTodos() {
        let completed = allTodos.filter(\.isCompleted)
        for todo in completed {
            modelContext.delete(todo)
        }
        do {
            try modelContext.save()
        } catch {
            print("\u{26a0}\u{fe0f} [\(#function)] Failed to delete completed todos: \(error)")
        }
    }

    func deleteTodo(_ todo: TodoItem) {
        adaptiveWithAnimation {
            modelContext.delete(todo)
            do {
                try modelContext.save()
            } catch {
                print("\u{26a0}\u{fe0f} [\(#function)] Failed to delete todo: \(error)")
            }
        }
    }

    func toggleSelection(_ todo: TodoItem) {
        if selectedTodoIDs.contains(todo.id) {
            selectedTodoIDs.remove(todo.id)
        } else {
            selectedTodoIDs.insert(todo.id)
        }
    }

    // MARK: - New Todo Sheet

    private var newTodoSheet: some View {
        NavigationStack {
            NewTodoForm()
                .navigationTitle("New Todo")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingNewTodo = false
                        }
                    }
                }
        }
    }
}
