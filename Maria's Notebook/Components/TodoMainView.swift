// TodoMainView.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

/// Main todo view with elegant layout inspired by Things and Bear
struct TodoMainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    
    @State private var selectedFilter: TodoListFilter? = .inbox
    @State private var searchText = ""
    @State private var selectedTodo: TodoItem?
    @State private var isShowingNewTodo = false
    @State private var isShowingTemplates = false
    @State private var isShowingExport = false
    @State private var editingTodo: TodoItem?
    @State private var showingSortOptions = false
    @State private var sortBy: TodoSortOption = .dueDate
    @State private var isSelectMode = false
    @State private var selectedTodoIDs: Set<UUID> = []
    @State private var selectedTag: String?
    @State private var expandedTagGroups: Set<String> = [TodoTagHelper.studentTagParent]
    
    private var filteredTodos: [TodoItem] {
        let todos: [TodoItem]
        if let tag = selectedTag {
            todos = allTodos.filter { $0.tags.contains(tag) }
        } else {
            let filter = selectedFilter ?? .inbox
            todos = allTodos.filter { filter.matches($0) }
        }
        
        let searchFiltered = searchText.isEmpty ? todos : todos.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
        
        return searchFiltered.sorted { lhs, rhs in
            // Completed items always go to bottom
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            
            // Then sort by selected option
            switch sortBy {
            case .dueDate:
                if let lhsDate = lhs.dueDate, let rhsDate = rhs.dueDate {
                    return lhsDate < rhsDate
                }
                return lhs.dueDate != nil && rhs.dueDate == nil
            case .priority:
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .created:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            
            Divider()
            
            if let selectedTodo = selectedTodo {
                TodoDetailView(todo: selectedTodo, onClose: {
                    self.selectedTodo = nil
                }, onEdit: {
                    editingTodo = selectedTodo
                })
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
                    withAnimation(.snappy(duration: 0.2)) {
                        isSelectMode.toggle()
                        if !isSelectMode { selectedTodoIDs.removeAll() }
                    }
                } label: {
                    Label(isSelectMode ? "Done" : "Select", systemImage: isSelectMode ? "checkmark.circle" : "checklist.unchecked")
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
        .sheet(item: $editingTodo) { todo in
            editTodoSheet(todo: todo)
        }
    }
    
    private func deleteCompletedTodos() {
        let completed = allTodos.filter(\.isCompleted)
        for todo in completed {
            modelContext.delete(todo)
        }
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to delete completed todos: \(error)")
        }
    }
    
    private func deleteTodo(_ todo: TodoItem) {
        withAnimation {
            modelContext.delete(todo)
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to delete todo: \(error)")
            }
        }
    }
    
    private func toggleSelection(_ todo: TodoItem) {
        if selectedTodoIDs.contains(todo.id) {
            selectedTodoIDs.remove(todo.id)
        } else {
            selectedTodoIDs.insert(todo.id)
        }
    }
    
    private func batchComplete() {
        withAnimation(.snappy(duration: 0.2)) {
            let todosToComplete = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todosToComplete {
                todo.isCompleted = true
                todo.completedAt = Date()
            }
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to batch complete: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
    
    private func batchSetHighPriority() {
        withAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todos {
                todo.priority = .high
            }
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to batch set priority: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
    
    private func batchSetDueToday() {
        withAnimation(.snappy(duration: 0.2)) {
            let todos = allTodos.filter { selectedTodoIDs.contains($0.id) }
            let today = Calendar.current.startOfDay(for: Date())
            for todo in todos {
                todo.dueDate = today
            }
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to batch set due date: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
    
    private func batchDelete() {
        withAnimation(.snappy(duration: 0.2)) {
            let todosToDelete = allTodos.filter { selectedTodoIDs.contains($0.id) }
            for todo in todosToDelete {
                modelContext.delete(todo)
            }
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to batch delete: \(error)")
            }
            selectedTodoIDs.removeAll()
            isSelectMode = false
        }
    }
    
    private func editTodoSheet(todo: TodoItem) -> some View {
        NavigationStack {
            EditTodoForm(todo: todo)
                .navigationTitle("Edit Todo")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            editingTodo = nil
                        }
                    }
                }
        }
    }
    
    // MARK: - Sidebar
    
    private var allUsedTags: [String] {
        var tagSet = Set<String>()
        for todo in allTodos {
            for tag in todo.tags {
                tagSet.insert(tag)
            }
        }
        return tagSet.sorted { TodoTagHelper.tagName($0).localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending }
    }

    private var topLevelTags: [String] {
        allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count <= 1 }
    }

    private var groupedNestedTags: [(group: String, tags: [String])] {
        let nested = allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count > 1 }
        let grouped = Dictionary(grouping: nested, by: { TodoTagHelper.rootTagName($0) })
        return grouped
            .map { (group: $0.key, tags: $0.value.sorted { TodoTagHelper.leafTagName($0).localizedCaseInsensitiveCompare(TodoTagHelper.leafTagName($1)) == .orderedAscending }) }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }
    
    private var sidebar: some View {
        List {
            Section {
                ForEach(TodoListFilter.allCases) { filter in
                    Button {
                        selectedTag = nil
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: filter.icon)
                                .foregroundStyle(filter.color)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 24)
                            
                            Text(filter.title)
                                .font(.system(size: 15))
                            
                            Spacer()
                            
                            if filter != .all {
                                Text("\(countForFilter(filter))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedTag == nil && selectedFilter == filter
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            
            if !allUsedTags.isEmpty {
                Section {
                    ForEach(topLevelTags, id: \.self) { tag in
                        Button {
                            selectedFilter = nil
                            selectedTag = tag
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(TodoTagHelper.tagColor(tag).color)
                                    .frame(width: 10, height: 10)
                                
                                Text(TodoTagHelper.tagName(tag))
                                    .font(.system(size: 15))
                                
                                Spacer()
                                
                                Text("\(countForTag(tag))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedTag == tag
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                    }

                    ForEach(groupedNestedTags, id: \.group) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedTagGroups.contains(group.group) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedTagGroups.insert(group.group)
                                    } else {
                                        expandedTagGroups.remove(group.group)
                                    }
                                }
                            )
                        ) {
                            ForEach(group.tags, id: \.self) { childTag in
                                Button {
                                    selectedFilter = nil
                                    selectedTag = childTag
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(TodoTagHelper.tagColor(childTag).color)
                                            .frame(width: 8, height: 8)

                                        Text(TodoTagHelper.leafTagName(childTag))
                                            .font(.system(size: 14))

                                        Spacer()

                                        Text("\(countForTag(childTag))")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(
                                    selectedTag == childTag
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 10)

                                Text(group.group)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Tags")
                        Spacer()
                        if hasUnusedTags {
                            Button("Remove Unused") {
                                removeUnusedTags()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Todo List Content
    
    private var todoListContent: some View {
        VStack(spacing: 0) {
            // Select mode header
            if isSelectMode {
                HStack {
                    Button {
                        if selectedTodoIDs.count == filteredTodos.count {
                            selectedTodoIDs.removeAll()
                        } else {
                            selectedTodoIDs = Set(filteredTodos.map(\.id))
                        }
                    } label: {
                        Text(selectedTodoIDs.count == filteredTodos.count ? "Deselect All" : "Select All")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.accent)
                    
                    Spacer()
                    
                    Text("\(selectedTodoIDs.count) selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Search bar
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, isSelectMode ? 4 : 16)
                .padding(.bottom, 12)
            
            if filteredTodos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedTodos.keys.sorted(), id: \.self) { section in
                            if let todos = groupedTodos[section], !todos.isEmpty {
                                todoSection(title: section, todos: todos)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isSelectMode ? 100 : 40)
                }
            }
            
            // Batch action bar
            if isSelectMode && !selectedTodoIDs.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .navigationTitle(selectedTag != nil ? TodoTagHelper.tagName(selectedTag!) : (selectedFilter ?? .inbox).title)
    }
    
    // MARK: - Batch Action Bar
    
    private var batchActionBar: some View {
        HStack(spacing: 0) {
            batchButton(title: "Complete", icon: "checkmark.circle", color: .green) {
                batchComplete()
            }
            
            Divider().frame(height: 30)
            
            batchButton(title: "Priority", icon: "flag", color: .orange) {
                batchSetHighPriority()
            }
            
            Divider().frame(height: 30)
            
            batchButton(title: "Today", icon: "calendar", color: .blue) {
                batchSetDueToday()
            }
            
            Divider().frame(height: 30)
            
            batchButton(title: "Delete", icon: "trash", color: .red) {
                batchDelete()
            }
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .background(.ultraThinMaterial)
        #else
        .background(.regularMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private func batchButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            
            TextField("Search todos", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    // MARK: - Grouped Todos
    
    private var groupedTodos: [String: [TodoItem]] {
        var groups: [String: [TodoItem]] = [:]
        
        for todo in filteredTodos {
            let section: String
            
            if selectedFilter == .completed {
                section = "Completed"
            } else if let dueDate = todo.dueDate {
                if Calendar.current.isDateInToday(dueDate) {
                    section = "Today"
                } else if Calendar.current.isDateInTomorrow(dueDate) {
                    section = "Tomorrow"
                } else if dueDate < Date() {
                    section = "Overdue"
                } else {
                    section = "Upcoming"
                }
            } else {
                section = "Anytime"
            }
            
            if groups[section] == nil {
                groups[section] = []
            }
            groups[section]?.append(todo)
        }
        
        return groups
    }
    
    private func todoSection(title: String, todos: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
                .padding(.top, 16)
                .padding(.bottom, 4)
            
            // Todo cards
            VStack(spacing: 1) {
                ForEach(todos) { todo in
                    HStack(spacing: 0) {
                        if isSelectMode {
                            Button {
                                toggleSelection(todo)
                            } label: {
                                Image(systemName: selectedTodoIDs.contains(todo.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selectedTodoIDs.contains(todo.id) ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        
                        TodoRowCard(todo: todo, onSelect: {
                            if isSelectMode {
                                toggleSelection(todo)
                            } else {
                                selectedTodo = todo
                            }
                        }, onEdit: {
                            editingTodo = todo
                        }, onDelete: {
                            deleteTodo(todo)
                        })
                    }
                }
            }
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            if let tag = selectedTag {
                Circle()
                    .fill(TodoTagHelper.tagColor(tag).color.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "tag")
                            .font(.system(size: 24, weight: .thin))
                            .foregroundStyle(TodoTagHelper.tagColor(tag).color)
                    }
            } else {
                Image(systemName: (selectedFilter ?? .inbox).icon)
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle((selectedFilter ?? .inbox).color.opacity(0.3))
            }
            
            Text(emptyStateMessage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            
            if selectedTag == nil && (selectedFilter == .inbox || selectedFilter == .all) {
                Button {
                    isShowingNewTodo = true
                } label: {
                    Label("New Todo", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No todos found"
        }
        if let tag = selectedTag {
            return "No todos tagged \"\(TodoTagHelper.tagName(tag))\""
        }
        return (selectedFilter ?? .inbox).emptyMessage
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
    
    // MARK: - Helper Functions
    
    private func countForFilter(_ filter: TodoListFilter) -> Int {
        guard filter != .all else { return 0 }
        return allTodos.filter { filter.matches($0) }.count
    }
    
    private func countForTag(_ tag: String) -> Int {
        allTodos.filter { $0.tags.contains(tag) }.count
    }
    
    private var hasUnusedTags: Bool {
        let activeTags = Set(allTodos.filter { !$0.isCompleted }.flatMap { $0.tags })
        let allTags = Set(allTodos.flatMap { $0.tags })
        return allTags.subtracting(activeTags).isEmpty == false
    }
    
    private func removeUnusedTags() {
        let activeTags = Set(allTodos.filter { !$0.isCompleted }.flatMap { $0.tags })
        let allTags = Set(allTodos.flatMap { $0.tags })
        let unusedTags = allTags.subtracting(activeTags)
        
        guard !unusedTags.isEmpty else { return }
        
        for todo in allTodos where todo.isCompleted {
            todo.tags.removeAll { unusedTags.contains($0) }
        }
        
        // Clear tag selection if the selected tag was removed
        if let selected = selectedTag, unusedTags.contains(selected) {
            selectedTag = nil
            selectedFilter = .inbox
        }
    }
}

// MARK: - Todo Filter

enum TodoListFilter: String, CaseIterable, Identifiable {
    case inbox
    case today
    case upcoming
    case anytime
    case completed
    case all
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .completed: return "Completed"
        case .all: return "All"
        }
    }
    
    var icon: String {
        switch self {
        case .inbox: return "tray.fill"
        case .today: return "star.fill"
        case .upcoming: return "calendar"
        case .anytime: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .all: return "list.bullet"
        }
    }
    
    var color: Color {
        switch self {
        case .inbox: return .blue
        case .today: return .orange
        case .upcoming: return .purple
        case .anytime: return .gray
        case .completed: return .green
        case .all: return .primary
        }
    }
    
    var emptyMessage: String {
        switch self {
        case .inbox: return "Your inbox is empty"
        case .today: return "No tasks scheduled for today"
        case .upcoming: return "No upcoming tasks"
        case .anytime: return "No unscheduled tasks"
        case .completed: return "No completed tasks yet"
        case .all: return "Add a task to get started"
        }
    }
    
    func matches(_ todo: TodoItem) -> Bool {
        switch self {
        case .inbox:
            return !todo.isCompleted && todo.tags.isEmpty
        case .today:
            return !todo.isCompleted && todo.isScheduledForToday
        case .upcoming:
            return !todo.isCompleted && todo.dueDate != nil && !todo.isScheduledForToday
        case .anytime:
            return !todo.isCompleted && todo.dueDate == nil
        case .completed:
            return todo.isCompleted
        case .all:
            return true
        }
    }
}

// MARK: - Todo Row Card

struct TodoRowCard: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 14) {
                // Checkbox
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        todo.isCompleted.toggle()
                        if todo.isCompleted {
                            todo.completedAt = Date()
                        } else {
                            todo.completedAt = nil
                        }
                        do {
                            try modelContext.save()
                        } catch {
                            print("⚠️ [\(#function)] Failed to save todo completion state: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(.system(size: 16))
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted)
                    
                    if !todo.notes.isEmpty || todo.dueDate != nil || !todo.tags.isEmpty {
                        HStack(spacing: 8) {
                            if let dueDate = todo.dueDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                    Text(formatDueDate(dueDate))
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                            }
                            
                            if !todo.tags.isEmpty {
                                ForEach(todo.tags.prefix(2), id: \.self) { tag in
                                    TagBadge(tag: tag, compact: true)
                                }
                                
                                if todo.tags.count > 2 {
                                    Text("+\(todo.tags.count - 2)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Priority indicator
                if todo.priority != .none {
                    Circle()
                        .fill(priorityColor(todo.priority))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button {
                togglePriority()
            } label: {
                Label("Change Priority", systemImage: "flag")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func togglePriority() {
        switch todo.priority {
        case .none: todo.priority = .low
        case .low: todo.priority = .medium
        case .medium: todo.priority = .high
        case .high: todo.priority = .none
        }
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save priority change: \(error)")
        }
    }
    
    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    private func formatDueDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        return date < Date() && !Calendar.current.isDateInToday(date)
    }
}

// MARK: - New Todo Form

struct NewTodoForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var allStudents: [Student]

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var priority: TodoPriority = .none
    @State private var recurrence: RecurrencePattern = .none
    @State private var selectedTags: [String] = []
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var subtaskTitles: [String] = []
    @State private var newSubtaskTitle = ""
    @State private var estimatedHours = 0
    @State private var estimatedMinutes = 0
    @State private var isCreatingTodo = false

    var body: some View {
        Form {
            // Title & Notes
            Section {
                TextField("What do you need to do?", text: $title)
                    .font(.system(size: 17))

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 15))
            }

            // Students
            if !allStudents.isEmpty {
                Section("Students") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allStudents) { student in
                                let isSelected = selectedStudentIDs.contains(student.id)
                                Button {
                                    if isSelected {
                                        selectedStudentIDs.remove(student.id)
                                    } else {
                                        selectedStudentIDs.insert(student.id)
                                    }
                                } label: {
                                    Text(student.firstName)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Schedule
            Section("Schedule") {
                Toggle("Due Date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])

                    Picker("Repeats", selection: $recurrence) {
                        ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                            Text(pattern.rawValue).tag(pattern)
                        }
                    }
                }
            }

            // Priority
            Section {
                Picker("Priority", selection: $priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { p in
                        HStack {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.rawValue)
                        }
                        .tag(p)
                    }
                }
            }

            // Subtasks / Checklist
            Section("Checklist") {
                ForEach(subtaskTitles.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Image(systemName: "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        Text(subtaskTitles[index])
                            .font(.system(size: 15))
                        Spacer()
                        Button {
                            subtaskTitles.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                    TextField("Add subtask", text: $newSubtaskTitle)
                        .font(.system(size: 15))
                        .onSubmit {
                            addSubtask()
                        }
                }
            }

            // Time Estimate
            Section("Time Estimate") {
                HStack {
                    Picker("Hours", selection: $estimatedHours) {
                        ForEach(0..<13) { h in Text("\(h)h").tag(h) }
                    }
                    .pickerStyle(.menu)
                    Picker("Minutes", selection: $estimatedMinutes) {
                        ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { m in Text("\(m)m").tag(m) }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Tags
            Section("Tags") {
                TagPicker(selectedTags: $selectedTags)
            }

            // Create
            Section {
                Button {
                    Task { await createTodo() }
                } label: {
                    HStack {
                        Spacer()
                        if isCreatingTodo {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label("Create Todo", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingTodo)
            }
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        newSubtaskTitle = ""
    }

    private func createTodo() async {
        isCreatingTodo = true
        defer { isCreatingTodo = false }

        let resolvedStudentIDs = await resolveStudentIDs()
        let resolvedStudentNames = allStudents
            .filter { resolvedStudentIDs.contains($0.id) }
            .map(\.fullName)
        let resolvedTags = TodoTagHelper.syncStudentTags(
            existingTags: selectedTags,
            studentNames: resolvedStudentNames
        )

        let todo = TodoItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            studentIDs: resolvedStudentIDs.map(\.uuidString),
            priority: priority
        )

        if hasDueDate {
            todo.dueDate = dueDate
            todo.recurrence = recurrence
        }

        todo.tags = resolvedTags

        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            todo.estimatedMinutes = totalEstimated
        }

        modelContext.insert(todo)

        // Create subtasks
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = TodoSubtask(title: subtaskTitle, orderIndex: index)
            subtask.todo = todo
            modelContext.insert(subtask)
        }

        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to create todo: \(error)")
        }
        dismiss()
    }

    private func resolveStudentIDs() async -> Set<UUID> {
        var resolved = selectedStudentIDs
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let combinedText = "\(title) \(notes)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard combinedText.isEmpty == false else { return resolved }

            do {
                let extractedNames = try await TodoStudentSuggestionService.extractStudentNames(
                    from: combinedText,
                    availableStudents: allStudents
                )
                let matchedStudents = TodoStudentSuggestionService.matchStudents(
                    extractedNames: extractedNames,
                    from: allStudents
                )
                resolved.formUnion(matchedStudents.map(\.id))
            } catch {
                // Fall back to manual student selection if extraction fails.
            }
        }
        #endif
        return resolved
    }
}

// MARK: - Todo Detail View

struct TodoDetailView: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var allStudents: [Student]
    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title + Checkbox
                HStack(alignment: .top, spacing: 14) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            todo.isCompleted.toggle()
                            todo.completedAt = todo.isCompleted ? Date() : nil
                            try? modelContext.save()
                        }
                    } label: {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28))
                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Text(todo.title)
                        .font(.system(size: 28, weight: .bold))
                        .strikethrough(todo.isCompleted)
                }

                // Students
                if !todo.studentIDs.isEmpty {
                    detailSection("Students", icon: "person.2.fill") {
                        FlowLayout(spacing: 8) {
                            ForEach(todo.studentUUIDs, id: \.self) { studentID in
                                let name = allStudents.first(where: { $0.id == studentID })
                                    .map { "\($0.firstName) \($0.lastName)" } ?? "Unknown"
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Due Date & Recurrence
                if todo.dueDate != nil || todo.recurrence != .none {
                    detailSection("Schedule", icon: "calendar") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let dueDate = todo.dueDate {
                                metadataRow(icon: "calendar", label: "Due", value: formatDate(dueDate), valueColor: todo.isOverdue ? .red : .secondary)
                            }
                            if todo.recurrence != .none {
                                metadataRow(icon: todo.recurrence.icon, label: "Repeats", value: todo.recurrence.description, valueColor: .purple)
                            }
                        }
                    }
                }

                // Priority
                if todo.priority != .none {
                    detailSection("Priority", icon: "flag.fill") {
                        HStack(spacing: 8) {
                            Circle().fill(todo.priority.color).frame(width: 10, height: 10)
                            Text(todo.priority.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(todo.priority.color)
                        }
                    }
                }

                // Tags
                if !todo.tags.isEmpty {
                    detailSection("Tags", icon: "tag.fill") {
                        FlowLayout(spacing: 8) {
                            ForEach(todo.tags, id: \.self) { tag in
                                TagBadge(tag: tag)
                            }
                        }
                    }
                }

                // Subtasks
                if !todo.subtasks.isEmpty {
                    detailSection("Checklist", icon: "checklist") {
                        VStack(alignment: .leading, spacing: 2) {
                            // Progress bar
                            let completed = todo.subtasks.filter(\.isCompleted).count
                            let total = todo.subtasks.count
                            HStack(spacing: 8) {
                                ProgressView(value: Double(completed), total: Double(total))
                                    .tint(completed == total ? .green : .accentColor)
                                Text("\(completed)/\(total)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 8)

                            ForEach(todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })) { subtask in
                                HStack(spacing: 10) {
                                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                    Text(subtask.title)
                                        .font(.system(size: 15))
                                        .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                                        .strikethrough(subtask.isCompleted)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Time Tracking
                if todo.estimatedMinutes != nil || todo.actualMinutes != nil {
                    detailSection("Time", icon: "clock.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let est = todo.estimatedMinutes {
                                metadataRow(icon: "hourglass", label: "Estimated", value: formatMinutes(est), valueColor: .secondary)
                            }
                            if let actual = todo.actualMinutes {
                                metadataRow(icon: "stopwatch", label: "Actual", value: formatMinutes(actual), valueColor: .secondary)
                            }
                            if let est = todo.estimatedMinutes, let actual = todo.actualMinutes, est > 0 {
                                let variance = actual - est
                                let color: Color = variance > 0 ? .red : (variance < 0 ? .green : .secondary)
                                metadataRow(icon: "chart.bar", label: "Variance", value: "\(variance > 0 ? "+" : "")\(formatMinutes(abs(variance)))", valueColor: color)
                            }
                        }
                    }
                }

                // Reminder
                if let reminderDate = todo.reminderDate {
                    detailSection("Reminder", icon: "bell.fill") {
                        metadataRow(icon: "bell", label: "Alert at", value: formatDate(reminderDate), valueColor: .yellow)
                    }
                }

                // Location Reminder
                if todo.hasLocationReminder, let locationName = todo.locationName {
                    detailSection("Location", icon: "location.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            metadataRow(icon: "mappin", label: "Place", value: locationName, valueColor: .teal)
                            HStack(spacing: 12) {
                                if todo.notifyOnEntry {
                                    Label("On arrival", systemImage: "arrow.right.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                if todo.notifyOnExit {
                                    Label("On departure", systemImage: "arrow.left.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Linked Work Item
                if todo.linkedWorkItemID != nil {
                    detailSection("Work Item", icon: "link") {
                        HStack(spacing: 6) {
                            Image(systemName: "briefcase.fill")
                                .foregroundStyle(.indigo)
                            Text("Linked work item")
                                .font(.system(size: 15))
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                // Attachments
                if todo.hasAttachments {
                    detailSection("Attachments", icon: "paperclip") {
                        Text("\(todo.attachmentPaths.count) file\(todo.attachmentPaths.count == 1 ? "" : "s")")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }

                // Mood & Reflection
                if todo.hasMoodOrReflection {
                    detailSection("Mood & Reflection", icon: "face.smiling") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let mood = todo.mood {
                                HStack(spacing: 8) {
                                    Text(mood.emoji)
                                        .font(.system(size: 24))
                                    Text(mood.rawValue)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(mood.color)
                                }
                            }
                            let reflection = todo.reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !reflection.isEmpty {
                                Text(reflection)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                // Notes
                if !todo.notes.isEmpty {
                    detailSection("Notes", icon: "text.alignleft") {
                        Text(todo.notes)
                            .font(.system(size: 15))
                    }
                }

                // Completed timestamp
                if todo.isCompleted, let completedAt = todo.completedAt {
                    detailSection("Completed", icon: "checkmark.seal.fill") {
                        metadataRow(icon: "checkmark", label: "Completed", value: formatDate(completedAt), valueColor: .green)
                    }
                }

                // Created timestamp
                detailSection("Created", icon: "clock.arrow.circlepath") {
                    metadataRow(icon: "plus.circle", label: "Created", value: formatDate(todo.createdAt), valueColor: .secondary)
                }
            }
            .padding(24)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .navigationTitle("")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Back") { onClose() }
            }
            ToolbarItem(placement: .automatic) {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            #endif
        }
    }

    // MARK: - Detail Helpers

    @ViewBuilder
    private func detailSection(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            content()
        }
    }

    private func metadataRow(icon: String, label: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(valueColor)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Edit Todo Form

struct EditTodoForm: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $todo.title)
                    .font(.system(size: 17))
                
                TextField("Notes", text: $todo.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 15))
            }
            
            Section("Schedule") {
                DatePicker("Due Date", selection: Binding(
                    get: { todo.dueDate ?? Date() },
                    set: { todo.dueDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                
                if todo.dueDate != nil {
                    Button("Clear Due Date") {
                        todo.dueDate = nil
                    }
                    .foregroundStyle(.red)
                }
            }
            
            Section("Organization") {
                Picker("Priority", selection: $todo.priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { p in
                        HStack {
                            Circle().fill(priorityColorForPicker(p)).frame(width: 8, height: 8)
                            Text(p.rawValue)
                        }
                        .tag(p)
                    }
                }
                
            }
            
            Section("Tags") {
                TagPicker(selectedTags: $todo.tags)
            }
            
            Section {
                Toggle("Completed", isOn: $todo.isCompleted)
                
                if todo.isCompleted, let completedAt = todo.completedAt {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text(formatCompletedDate(completedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .onChange(of: todo) {
            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to save todo changes: \(error)")
            }
        }
    }
    
    private func priorityColorForPicker(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    private func formatCompletedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Todo Sort Option

enum TodoSortOption: String, CaseIterable, Identifiable {
    case dueDate = "Due Date"
    case priority = "Priority"
    case title = "Title"
    case created = "Created"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
}

// MARK: - Tag Badge Component

struct TagBadge: View {
    let tag: String
    var compact: Bool = false
    
    private var tagName: String {
        if TodoTagHelper.isStudentTag(tag) {
            return TodoTagHelper.leafTagName(tag)
        }
        return TodoTagHelper.tagName(tag)
    }
    
    private var tagColor: TagColor {
        TodoTagHelper.tagColor(tag)
    }
    
    var body: some View {
        Text(tagName)
            .font(.system(size: compact ? 11 : 13, weight: .medium))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(tagColor.lightColor)
            .foregroundStyle(tagColor.color)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6))
    }
}

// MARK: - Tag Picker Component

struct TagPicker: View {
    @Binding var selectedTags: [String]
    @State private var isShowingCustomTagSheet = false
    @State private var searchText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search/Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                
                TextField("Search tags", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(.systemGray6))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Common tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredCommonTags, id: \.0) { name, color in
                        let tag = TodoTagHelper.createTag(name: name, color: color)
                        TagButton(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onToggle: { toggleTag(tag) }
                        )
                    }
                    
                    Button {
                        isShowingCustomTagSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("New Tag")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        #if os(iOS)
                        .background(Color(.systemGray5))
                        #else
                        .background(Color(nsColor: .controlBackgroundColor))
                        #endif
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // Selected tags
            if !selectedTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Tags")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(selectedTags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                TagBadge(tag: tag)
                                
                                Button {
                                    selectedTags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingCustomTagSheet) {
            CustomTagSheet(selectedTags: $selectedTags)
        }
    }
    
    private var filteredCommonTags: [(String, TagColor)] {
        if searchText.isEmpty {
            return TodoTagHelper.commonTags
        }
        return TodoTagHelper.commonTags.filter {
            $0.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }
}

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    private var tagName: String {
        TodoTagHelper.tagName(tag)
    }
    
    private var tagColor: TagColor {
        TodoTagHelper.tagColor(tag)
    }
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                }
                Text(tagName)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tagColor.color : tagColor.lightColor)
            .foregroundStyle(isSelected ? .white : tagColor.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct CustomTagSheet: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var tagName = ""
    @State private var selectedColor: TagColor = .blue
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Enter tag name", text: $tagName)
                }
                
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                        ForEach(TagColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                    
                                    Text(color.rawValue)
                                        .font(.system(size: 11))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Tag")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let tag = TodoTagHelper.createTag(name: tagName, color: selectedColor)
                        selectedTags.append(tag)
                        dismiss()
                    }
                    .disabled(tagName.isEmpty)
                }
            }
        }
    }
}

// MARK: - TodoItem Extension

extension TodoItem {
    var isScheduledForToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}
