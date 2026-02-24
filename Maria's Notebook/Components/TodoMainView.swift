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
    
    private var filteredTodos: [TodoItem] {
        let todos: [TodoItem]

        switch selectedFilter ?? .inbox {
        case .inbox:
            todos = allTodos.filter { !$0.isCompleted && $0.tags.isEmpty }
        case .today:
            todos = allTodos.filter { !$0.isCompleted && $0.isScheduledForToday }
        case .upcoming:
            todos = allTodos.filter { !$0.isCompleted && $0.dueDate != nil && !$0.isScheduledForToday }
        case .anytime:
            todos = allTodos.filter { !$0.isCompleted && $0.dueDate == nil }
        case .completed:
            todos = allTodos.filter { $0.isCompleted }
        case .all:
            todos = allTodos
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
        NavigationSplitView {
            sidebar
        } detail: {
            if let selectedTodo = selectedTodo {
                TodoDetailView(todo: selectedTodo, onClose: {
                    self.selectedTodo = nil
                }, onEdit: {
                    editingTodo = selectedTodo
                })
            } else {
                todoListContent
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
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
    
    private var sidebar: some View {
        List(selection: $selectedFilter) {
            Section {
                ForEach(TodoListFilter.allCases) { filter in
                    NavigationLink(value: filter) {
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
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Todos")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    // MARK: - Todo List Content
    
    private var todoListContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
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
                    .padding(.bottom, 40)
                }
            }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .navigationTitle((selectedFilter ?? .inbox).title)
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
                    TodoRowCard(todo: todo, onSelect: {
                        selectedTodo = todo
                    }, onEdit: {
                        editingTodo = todo
                    }, onDelete: {
                        deleteTodo(todo)
                    })
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
            Image(systemName: (selectedFilter ?? .inbox).icon)
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle((selectedFilter ?? .inbox).color.opacity(0.3))
            
            Text(emptyStateMessage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            
            if selectedFilter == .inbox || selectedFilter == .all {
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
        
        switch selectedFilter ?? .inbox {
        case .inbox: return "No todos in inbox"
        case .today: return "Nothing scheduled for today"
        case .upcoming: return "No upcoming todos"
        case .anytime: return "No todos without a date"
        case .completed: return "No completed todos"
        case .all: return "No todos yet"
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
    
    // MARK: - Helper Functions
    
    private func countForFilter(_ filter: TodoListFilter) -> Int {
        switch filter {
        case .inbox:
            return allTodos.filter { !$0.isCompleted && $0.tags.isEmpty }.count
        case .today:
            return allTodos.filter { !$0.isCompleted && $0.isScheduledForToday }.count
        case .upcoming:
            return allTodos.filter { !$0.isCompleted && $0.dueDate != nil && !$0.isScheduledForToday }.count
        case .anytime:
            return allTodos.filter { !$0.isCompleted && $0.dueDate == nil }.count
        case .completed:
            return allTodos.filter { $0.isCompleted }.count
        case .all:
            return 0
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
    
    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var priority: TodoPriority = .none
    @State private var selectedTags: [String] = []
    
    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .font(.system(size: 17))
                
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 15))
            }
            
            Section {
                Toggle("Due Date", isOn: $hasDueDate)
                
                if hasDueDate {
                    DatePicker("Date", selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
            }
            
            Section {
                Picker("Priority", selection: $priority) {
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
                TagPicker(selectedTags: $selectedTags)
            }
            
            Section {
                Button("Create Todo") {
                    createTodo()
                }
                .disabled(title.isEmpty)
            }
        }
    }
    
    private func createTodo() {
        let todo = TodoItem(
            title: title,
            notes: notes,
            studentIDs: [],
            priority: priority
        )
        
        if hasDueDate {
            todo.dueDate = dueDate
        }
        
        todo.tags = selectedTags

        modelContext.insert(todo)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to create todo: \(error)")
        }
        dismiss()
    }
    
    private func priorityColorForPicker(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Todo Detail View

struct TodoDetailView: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    let onClose: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
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
                        } label: {
                            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 28))
                                .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text(todo.title)
                            .font(.system(size: 28, weight: .bold))
                            .strikethrough(todo.isCompleted)
                    }
                }
                
                // Notes
                if !todo.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Text(todo.notes)
                            .font(.system(size: 15))
                    }
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    if let dueDate = todo.dueDate {
                        metadataRow(icon: "calendar", label: "Due", value: formatDate(dueDate))
                    }
                    
                    if todo.priority != .none {
                        HStack {
                            Image(systemName: "flag")
                            Text("Priority")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(priorityColorForDetail(todo.priority)).frame(width: 8, height: 8)
                                Text(todo.priority.rawValue)
                            }
                        }
                        .font(.system(size: 15))
                    }
                    
                }
                
                // Tags
                if !todo.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(todo.tags, id: \.self) { tag in
                                TagBadge(tag: tag)
                            }
                        }
                    }
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
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Back") {
                    onClose()
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            #endif
        }
    }
    
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 15))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func priorityColorForDetail(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
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
        TodoTagHelper.tagName(tag)
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
