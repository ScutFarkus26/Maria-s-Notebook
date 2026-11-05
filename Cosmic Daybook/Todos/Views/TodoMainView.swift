// TodoMainView.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import CoreData

/// Main todo view with elegant layout inspired by Things and Bear
struct TodoMainView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)])
    var allTodos: FetchedResults<CDTodoItem>

    @State var selectedFilter: TodoListFilter? = .checkIns
    @State var searchText = ""
    @State var selectedTodo: CDTodoItem?
    @State var isShowingNewTodo = false
    @State var sortBy: TodoSortOption = .dueDate
    @State var isSelectMode = false
    @State var batchSelection = TodoBatchSelection()
    @AppStorage(UserDefaultsKeys.todoHideCompleted) var hideCompleted = false
    /// A Tide list picked under "From Tide", by workspace path.
    @State var selectedTideList: String?
    @State private var isShowingCompactList = false
    /// Clear Completed and batch Delete ask first, with the count they
    /// delete (bug hunt 2026-11-03, #50, #51).
    @State var pendingClearCount: Int?
    @State var pendingBatchDeleteCount: Int?
    /// The day the lists and headings are counted on, moved on at midnight
    /// (bug hunt 2026-11-03, #56).
    @State var calendarDay = AppCalendar.startOfDay(Date())
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // PERF: Cached computed results to avoid recomputing on every body evaluation.
    // Refreshed via .onChange handlers when source data changes.
    @State var cachedFilterCounts: [TodoListFilter: Int] = [:]
    /// Open shared to-dos per Tide list, by workspace path.
    @State var cachedTideListCounts: [String: Int] = [:]

    var body: some View {
        layout
            .sheet(isPresented: $isShowingNewTodo) {
                newTodoSheet
            }
            .onAppear { refreshTagCaches() }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            ) { note in
                if Self.changesTodoCounts(note) { refreshTagCaches() }
            }
            .onChange(of: hideCompleted) { _, _ in refreshTagCaches() }
            .onChange(of: listScope, initial: true) { _, scope in batchSelection.show(scope) }
            .onCalendarDayChange {
                calendarDay = AppCalendar.startOfDay(Date())
                refreshTagCaches()
            }
            .confirmationDialog(
                Self.deleteQuestion(count: pendingClearCount ?? 0, completed: true),
                isPresented: isAsking($pendingClearCount),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteCompletedTodos() }
            } message: {
                Text("This can't be undone.")
            }
            .confirmationDialog(
                Self.deleteQuestion(count: pendingBatchDeleteCount ?? 0, completed: false),
                isPresented: isAsking($pendingBatchDeleteCount),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { batchDelete() }
            } message: {
                Text("This can't be undone.")
            }
    }

    // MARK: - Layout

    /// The filter list beside the todos on a wide screen. A phone has no room
    /// for both: the filter list fills the screen, a filter pushes its todos,
    /// and a todo pushes its editor.
    @ViewBuilder
    private var layout: some View {
        if isCompactLayout {
            sidebar
                .navigationTitle("Todos")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        moreMenu
                        newTodoButton
                    }
                }
                .navigationDestination(isPresented: $isShowingCompactList) {
                    todoListContent
                        .toolbar { listToolbar }
                        .navigationDestination(item: $selectedTodo) { todo in
                            EditTodoForm(todo: todo)
                                .navigationTitle("Edit Todo")
                        }
                }
        } else {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(width: 220)

                Divider()

                if let selectedTodo {
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
            .toolbar { listToolbar }
        }
    }

    /// How to add a task, in the platform's terms: a Mac has ⌘N; an iPhone or
    /// iPad without a keyboard has only the + button.
    static var newTaskHint: Text {
        #if os(macOS)
        Text("Press \(Image(systemName: "command")) N to add a new task")
        #else
        Text("Tap \(Image(systemName: "plus")) to add a new task")
        #endif
    }

    /// Opens the chosen filter's todos, on a phone, where they don't share
    /// the screen with the filter list.
    func showSelectedListIfCompact() {
        if isCompactLayout {
            isShowingCompactList = true
        }
    }

    private var isCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
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

            moreMenu

            newTodoButton
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                hideCompleted.toggle()
                refreshTagCaches()
            } label: {
                Label(
                    hideCompleted ? "Show Completed" : "Hide Completed",
                    systemImage: hideCompleted ? "eye" : "eye.slash"
                )
            }

            // Only the shown list's completed to-dos, after asking.
            let completedCount = listScope.completedToClear(from: Array(allTodos)).count
            Button(role: .destructive) {
                pendingClearCount = completedCount
            } label: {
                Label("Clear Completed", systemImage: "trash")
            }
            .disabled(completedCount == 0)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var newTodoButton: some View {
        Button {
            isShowingNewTodo = true
        } label: {
            Label("New Todo", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }

    // MARK: - Helper Functions

    private func deleteCompletedTodos() {
        let completed = listScope.completedToClear(from: Array(allTodos))
        for todo in completed {
            viewContext.delete(todo)
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Clear completed todos")
    }

    func deleteTodo(_ todo: CDTodoItem) {
        adaptiveWithAnimation {
            viewContext.delete(todo)
            dependencies.saveCoordinator.save(viewContext, reason: "Delete todo")
        }
    }

    func toggleSelection(_ todo: CDTodoItem) {
        guard let id = todo.id else { return }
        if selectedTodoIDs.contains(id) {
            selectedTodoIDs.remove(id)
        } else {
            selectedTodoIDs.insert(id)
        }
    }
}
