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
    @State private var showingSortOptions = false
    @State private var sortBy: TodoSortOption = .dueDate
    @State private var isSelectMode = false
    @State private var selectedTodoIDs: Set<UUID> = []
    @State private var selectedTag: String?
    @State private var expandedTagGroups: Set<String> = [TodoTagHelper.studentTagParent]
    @State private var tagOrder: [String] = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.todoTagOrder) ?? []
    @State private var selectedFolder: String?
    @State private var isShowingNewFolder = false
    @State private var newFolderName = ""
    @State private var draggingTag: String?
    
    private var filteredTodos: [TodoItem] {
        let todos: [TodoItem]
        if let folder = selectedFolder {
            // Show all todos that have any tag belonging to this folder
            let folderTags = Set(allUsedTags.filter {
                TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == folder
            })
            todos = allTodos.filter { todo in
                todo.tags.contains(where: { folderTags.contains($0) })
            }
        } else if let tag = selectedTag {
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
                if let lhsDate = lhs.effectiveDate, let rhsDate = rhs.effectiveDate {
                    return lhsDate < rhsDate
                }
                return lhs.effectiveDate != nil && rhs.effectiveDate == nil
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
        .sheet(isPresented: $isShowingNewFolder) {
            newFolderSheet
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

    /// All sidebar items (top-level tags + group names) in user-defined order.
    /// Items not yet in tagOrder are appended alphabetically.
    private var orderedSidebarItems: [String] {
        // Collect unique sidebar entries: top-level tag strings and group folder names (prefixed with "folder:")
        var items: [String] = []
        var seen = Set<String>()

        for tag in allUsedTags {
            let components = TodoTagHelper.tagPathComponents(tag)
            if components.count <= 1 {
                // top-level tag
                if seen.insert(tag).inserted { items.append(tag) }
            } else {
                // nested – represent folder by its root name
                let folderKey = "folder:" + TodoTagHelper.rootTagName(tag)
                if seen.insert(folderKey).inserted { items.append(folderKey) }
            }
        }

        // Also include empty folders from tagOrder that don't match any current tags
        for key in tagOrder where key.hasPrefix("folder:") && !seen.contains(key) {
            seen.insert(key)
            items.append(key)
        }

        // Sort by position in tagOrder; unknowns go to the end in their natural order
        let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: tagOrder.enumerated().map { ($1, $0) })
        return items.sorted { lhs, rhs in
            let lhsIdx = orderMap[lhs] ?? Int.max
            let rhsIdx = orderMap[rhs] ?? Int.max
            if lhsIdx != rhsIdx { return lhsIdx < rhsIdx }
            // Both unknown – fall back to alphabetical
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    private func displayName(for sidebarItem: String) -> String {
        if sidebarItem.hasPrefix("folder:") {
            return String(sidebarItem.dropFirst("folder:".count))
        }
        return TodoTagHelper.tagName(sidebarItem)
    }

    private var topLevelTags: [String] {
        allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count <= 1 }
    }

    private func nestedTags(forGroup group: String) -> [String] {
        let nested = allUsedTags.filter {
            TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == group
        }
        // Sort children by position in tagOrder, then alphabetically
        let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: tagOrder.enumerated().map { ($1, $0) })
        return nested.sorted { lhs, rhs in
            let lhsIdx = orderMap[lhs] ?? Int.max
            let rhsIdx = orderMap[rhs] ?? Int.max
            if lhsIdx != rhsIdx { return lhsIdx < rhsIdx }
            return TodoTagHelper.leafTagName(lhs).localizedCaseInsensitiveCompare(TodoTagHelper.leafTagName(rhs)) == .orderedAscending
        }
    }

    private var groupedNestedTags: [(group: String, tags: [String])] {
        let nested = allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count > 1 }
        let grouped = Dictionary(grouping: nested, by: { TodoTagHelper.rootTagName($0) })
        return grouped
            .map { (group: $0.key, tags: $0.value.sorted { TodoTagHelper.leafTagName($0).localizedCaseInsensitiveCompare(TodoTagHelper.leafTagName($1)) == .orderedAscending }) }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    private func persistTagOrder() {
        UserDefaults.standard.set(tagOrder, forKey: UserDefaultsKeys.todoTagOrder)
    }

    private func moveTag(from source: String, toAfter destination: String) {
        // Build full ordered list if empty
        if tagOrder.isEmpty {
            tagOrder = orderedSidebarItems
        }
        // Ensure both are in the list
        if !tagOrder.contains(source) { tagOrder.append(source) }
        if !tagOrder.contains(destination) { tagOrder.append(destination) }
        // Remove source
        tagOrder.removeAll { $0 == source }
        // Insert after destination
        if let destIdx = tagOrder.firstIndex(of: destination) {
            tagOrder.insert(source, at: destIdx + 1)
        } else {
            tagOrder.append(source)
        }
        persistTagOrder()
    }
    
    private var sidebar: some View {
        List {
            Section {
                ForEach(TodoListFilter.allCases) { filter in
                    let isActive = selectedTag == nil && selectedFolder == nil && selectedFilter == filter
                    Button {
                        selectedTag = nil
                        selectedFolder = nil
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(filter.color)
                                .frame(width: 28, height: 28)
                                .background(filter.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                            Text(filter.title)
                                .font(.system(size: 15, weight: isActive ? .semibold : .regular))

                            Spacer()

                            if filter != .all {
                                let count = countForFilter(filter)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        isActive
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                    )
                }
            }
            
            if !allUsedTags.isEmpty || tagOrder.contains(where: { $0.hasPrefix("folder:") }) {
                Section {
                    ForEach(orderedSidebarItems, id: \.self) { item in
                        if item.hasPrefix("folder:") {
                            let groupName = String(item.dropFirst("folder:".count))
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedTagGroups.contains(groupName) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedTagGroups.insert(groupName)
                                        } else {
                                            expandedTagGroups.remove(groupName)
                                        }
                                    }
                                )
                            ) {
                                ForEach(nestedTags(forGroup: groupName), id: \.self) { childTag in
                                    tagRow(
                                        tag: childTag,
                                        displayName: TodoTagHelper.leafTagName(childTag),
                                        dotSize: 8,
                                        fontSize: 14,
                                        dragKey: childTag
                                    )
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedFolder == groupName ? "folder.fill" : "folder")
                                        .foregroundStyle(selectedFolder == groupName ? Color.accentColor : .secondary)
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 10)

                                    Text(groupName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(selectedFolder == groupName ? Color.accentColor : .primary)

                                    Spacer()

                                    if selectedFolder == groupName {
                                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        if selectedFolder == groupName {
                                            // Deselect folder
                                            selectedFolder = nil
                                            selectedFilter = .inbox
                                        } else {
                                            // Select folder — show all items with tags in this folder
                                            selectedFolder = groupName
                                            selectedTag = nil
                                            selectedFilter = nil
                                        }
                                    }
                                }
                                .draggable(item) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(groupName)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let dropped = items.first, dropped != item else { return false }
                                    withAnimation(.snappy(duration: 0.2)) {
                                        moveTag(from: dropped, toAfter: item)
                                    }
                                    return true
                                }
                            }
                        } else {
                            tagRow(
                                tag: item,
                                displayName: TodoTagHelper.tagName(item),
                                dotSize: 10,
                                fontSize: 15,
                                dragKey: item
                            )
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
                        Button {
                            newFolderName = ""
                            isShowingNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Tag Row Helper

    private func tagRow(tag: String, displayName: String, dotSize: CGFloat, fontSize: CGFloat, dragKey: String) -> some View {
        Button {
            selectedFilter = nil
            selectedFolder = nil
            selectedTag = tag
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(TodoTagHelper.tagColor(tag).color)
                    .frame(width: dotSize, height: dotSize)
                    .contentShape(.dragPreview, Circle())
                    .draggable(dragKey) {
                        Circle()
                            .fill(TodoTagHelper.tagColor(tag).color)
                            .frame(width: dotSize + 4, height: dotSize + 4)
                    }

                Text(displayName)
                    .font(.system(size: fontSize))

                Spacer()

                Text("\(countForTag(tag))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedTag == tag
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first, dropped != dragKey else { return false }
            withAnimation(.snappy(duration: 0.2)) {
                moveTag(from: dropped, toAfter: dragKey)
            }
            return true
        }
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
                        ForEach(sortedSectionKeys, id: \.self) { section in
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
        .navigationTitle(selectedFolder ?? (selectedTag != nil ? TodoTagHelper.tagName(selectedTag!) : (selectedFilter ?? .inbox).title))
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
                .foregroundStyle(.tertiary)
                .font(.system(size: 14))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(Capsule(style: .continuous))
    }
    
    // MARK: - Grouped Todos
    
    private var groupedTodos: [String: [TodoItem]] {
        var groups: [String: [TodoItem]] = [:]
        let cal = Calendar.current
        let today = AppCalendar.startOfDay(Date())
        
        // For Upcoming filter, use day-by-day timeline
        let useDayTimeline = selectedFilter == .upcoming
        
        for todo in filteredTodos {
            let section: String
            
            if selectedFilter == .completed {
                section = "Completed"
            } else if selectedFilter == .someday {
                section = "Someday"
            } else if let effective = todo.effectiveDate {
                if todo.isOverdue {
                    section = "Overdue"
                } else if cal.isDateInToday(effective) {
                    section = "Today"
                } else if cal.isDateInTomorrow(effective) {
                    section = useDayTimeline ? dayTimelineKey(effective) : "Tomorrow"
                } else if effective < today {
                    section = "Overdue"
                } else if useDayTimeline {
                    // Day-by-day grouping for upcoming timeline
                    let weeksAhead = cal.dateComponents([.day], from: today, to: effective).day ?? 0
                    if weeksAhead <= 28 {
                        section = dayTimelineKey(effective)
                    } else {
                        section = "Later"
                    }
                } else {
                    section = "Upcoming"
                }
            } else if todo.isSomeday {
                section = "Someday"
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
    
    /// Sorted section keys for display order in the grouped todos view.
    private var sortedSectionKeys: [String] {
        let keys = groupedTodos.keys
        let order = ["Overdue", "Today", "Tomorrow"]
        
        var sorted: [String] = []
        // Add known sections first in order
        for key in order where keys.contains(key) {
            sorted.append(key)
        }
        // Add day-timeline keys sorted by date
        let dayKeys = keys.filter { $0.contains(",") }.sorted { a, b in
            // Parse "EEE, MMM d" format for sorting
            dayTimelineDate(a) ?? .distantFuture < dayTimelineDate(b) ?? .distantFuture
        }
        sorted.append(contentsOf: dayKeys)
        // Add remaining keys
        let remaining = ["Upcoming", "Anytime", "Someday", "Later", "Completed"]
        for key in remaining where keys.contains(key) {
            sorted.append(key)
        }
        return sorted
    }
    
    private func dayTimelineKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func dayTimelineDate(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        // Set the year context for parsing
        formatter.defaultDate = AppCalendar.startOfDay(Date())
        return formatter.date(from: key)
    }
    
    private func todoSection(title: String, todos: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Things-style section header
            HStack(spacing: 10) {
                sectionIcon(for: title)
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(todos.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Todo rows with thin dividers
            VStack(spacing: 0) {
                ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                    VStack(spacing: 0) {
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
                                selectedTodo = todo
                            }, onDelete: {
                                deleteTodo(todo)
                            })
                        }

                        if index < todos.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func sectionIcon(for title: String) -> some View {
        let config = sectionIconConfig(for: title)
        Image(systemName: config.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(config.color)
            .frame(width: 26, height: 26)
            .background(config.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func sectionIconConfig(for title: String) -> (icon: String, color: Color) {
        switch title {
        case "Overdue": return ("exclamationmark.triangle.fill", .red)
        case "Today": return ("star.fill", .orange)
        case "Tomorrow": return ("sunrise.fill", .orange)
        case "Upcoming": return ("calendar", .purple)
        case "Anytime": return ("tray.fill", .blue)
        case "Someday": return ("moon.zzz.fill", .mint)
        case "Later": return ("calendar.badge.clock", .secondary)
        case "Completed": return ("checkmark.circle.fill", .green)
        default: return ("calendar", .secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            if selectedFolder != nil {
                Image(systemName: "folder")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.quaternary)
            } else if let tag = selectedTag {
                Circle()
                    .fill(TodoTagHelper.tagColor(tag).color.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "tag")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(TodoTagHelper.tagColor(tag).color.opacity(0.6))
                    }
            } else {
                let filter = selectedFilter ?? .inbox
                Image(systemName: filter.icon)
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(filter.color.opacity(0.25))
            }

            VStack(spacing: 6) {
                Text(emptyStateMessage)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if selectedTag == nil && selectedFolder == nil && (selectedFilter == .inbox || selectedFilter == .all) {
                    Text("Press \(Image(systemName: "command")) N to add a new task")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No todos found"
        }
        if let folder = selectedFolder {
            return "No todos in \"\(folder)\""
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
    
    // MARK: - New Folder Sheet

    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Enter folder name", text: $newFolderName)
                }
            }
            .navigationTitle("New Tag Folder")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingNewFolder = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let folderKey = "folder:" + trimmed
                        if !tagOrder.contains(folderKey) {
                            if tagOrder.isEmpty {
                                tagOrder = orderedSidebarItems
                            }
                            tagOrder.append(folderKey)
                            persistTagOrder()
                        }
                        expandedTagGroups.insert(trimmed)
                        isShowingNewFolder = false
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    case someday
    case completed
    case all
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
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
        case .someday: return "moon.zzz"
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
        case .someday: return .brown
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
        case .someday: return "No someday tasks"
        case .completed: return "No completed tasks yet"
        case .all: return "Add a task to get started"
        }
    }
    
    func matches(_ todo: TodoItem) -> Bool {
        switch self {
        case .inbox:
            return !todo.isCompleted && !todo.isSomeday && todo.tags.isEmpty
        case .today:
            return !todo.isCompleted && !todo.isSomeday && todo.isScheduledForToday
        case .upcoming:
            let hasDate = todo.scheduledDate != nil || todo.dueDate != nil
            return !todo.isCompleted && !todo.isSomeday && hasDate && !todo.isScheduledForToday
        case .anytime:
            return !todo.isCompleted && !todo.isSomeday && todo.scheduledDate == nil && todo.dueDate == nil
        case .someday:
            return !todo.isCompleted && todo.isSomeday
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

    @State private var checkboxScale: CGFloat = 1.0

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 0) {
                // Priority left-edge bar
                if todo.priority != .none {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(priorityColor(todo.priority))
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.trailing, 11)
                } else {
                    Spacer()
                        .frame(width: 14)
                }

                // Checkbox
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        checkboxScale = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                            todo.isCompleted.toggle()
                            todo.completedAt = todo.isCompleted ? Date() : nil
                            checkboxScale = 1.0
                            do {
                                try modelContext.save()
                            } catch {
                                print("⚠️ [\(#function)] Failed to save todo completion state: \(error)")
                            }
                        }
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(todo.isCompleted ? .secondary : .tertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(checkboxScale)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .sensoryFeedback(.success, trigger: todo.isCompleted)
                #endif

                Spacer().frame(width: 14)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(.system(size: 17))
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted, color: .secondary.opacity(0.5))

                    if !todo.notes.isEmpty {
                        Text(todo.notes)
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if todo.effectiveDate != nil || todo.isSomeday || !todo.tags.isEmpty || todo.recurrence != .none {
                        HStack(spacing: 6) {
                            if todo.effectiveDate != nil || todo.isSomeday {
                                TodoDateChip(todo: todo)
                            }

                            if todo.recurrence != .none {
                                HStack(spacing: 3) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 10))
                                    Text(todo.recurrence.shortLabel)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.purple.opacity(0.7))
                            }

                            if !todo.tags.isEmpty {
                                fittingTagBadges(todo.tags)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                // Subtask count
                if let progressText = todo.subtasksProgressText {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11))
                        Text(progressText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(todo.allSubtasksCompleted ? .green.opacity(0.7) : .secondary.opacity(0.5))
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
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
        .swipeActions(edge: .leading) {
            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Date())
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("Today", systemImage: "star.fill")
            }
            .tint(.orange)

            Button {
                todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(.orange.opacity(0.8))

            Button {
                todo.scheduledDate = nextMonday()
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("+1 Week", systemImage: "calendar.badge.plus")
            }
            .tint(.purple)
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

            Menu("Move to...") {
                Button {
                    todo.scheduledDate = AppCalendar.startOfDay(Date())
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Today", systemImage: "star.fill")
                }
                Button {
                    todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                Button {
                    todo.scheduledDate = nextMonday()
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
                Button {
                    todo.scheduledDate = nil
                    todo.isSomeday = true
                    try? modelContext.save()
                } label: {
                    Label("Someday", systemImage: "moon.zzz")
                }
                Divider()
                Button {
                    todo.scheduledDate = nil
                    todo.dueDate = nil
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Remove Date", systemImage: "xmark.circle")
                }
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

    private func nextMonday() -> Date {
        let today = AppCalendar.startOfDay(Date())
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: today) ?? today
        while cal.component(.weekday, from: d) != 2 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    @ViewBuilder
    private func fittingTagBadges(_ tags: [String]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: tags.count, through: 1, by: -1)), id: \.self) { visibleCount in
                tagBadgeRow(tags: tags, visibleCount: visibleCount)
            }

            Text("+\(tags.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func tagBadgeRow(tags: [String], visibleCount: Int) -> some View {
        let visibleTags = Array(tags.prefix(visibleCount))
        let hiddenCount = max(tags.count - visibleCount, 0)

        return HStack(spacing: 6) {
            ForEach(Array(visibleTags.enumerated()), id: \.offset) { _, tag in
                TagBadge(tag: tag, compact: true)
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - New Todo Form

struct NewTodoForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var allStudents: [Student]

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date? = nil
    @State private var scheduledDate: Date? = nil
    @State private var isSomeday = false
    @State private var priority: TodoPriority = .none
    @State private var recurrence: RecurrencePattern = .none
    @State private var repeatAfterCompletion = false
    @State private var customIntervalDays = 7
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
                HStack {
                    Text("When")
                    Spacer()
                    TodoSchedulePickerButton(
                        scheduledDate: $scheduledDate,
                        dueDate: $dueDate,
                        isSomeday: $isSomeday
                    )
                }

                Picker("Repeats", selection: $recurrence) {
                    ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }

                if recurrence != .none {
                    Toggle("Repeat after completion", isOn: $repeatAfterCompletion)
                    if recurrence == .custom {
                        Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
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
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            priority: priority,
            recurrence: recurrence
        )
        todo.isSomeday = isSomeday
        todo.repeatAfterCompletion = repeatAfterCompletion
        if recurrence == .custom {
            todo.customIntervalDays = customIntervalDays
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
                if todo.dueDate != nil || todo.scheduledDate != nil || todo.isSomeday || todo.recurrence != .none {
                    detailSection("Schedule", icon: "calendar") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let scheduled = todo.scheduledDate {
                                metadataRow(icon: "star", label: "Scheduled", value: formatDate(scheduled), valueColor: .blue)
                            }
                            if let dueDate = todo.dueDate {
                                metadataRow(icon: "flag.fill", label: "Deadline", value: formatDate(dueDate), valueColor: todo.isOverdue ? .red : .orange)
                            }
                            if todo.isSomeday {
                                metadataRow(icon: "moon.zzz", label: "Status", value: "Someday", valueColor: .secondary)
                            }
                            if todo.recurrence != .none {
                                metadataRow(icon: todo.recurrence.icon, label: "Repeats", value: todo.recurrence.description, valueColor: .purple)
                            }
                            if todo.repeatAfterCompletion {
                                metadataRow(icon: "arrow.clockwise", label: "Mode", value: "After completion", valueColor: .purple)
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
                HStack {
                    Text("When")
                    Spacer()
                    TodoSchedulePickerButton(
                        scheduledDate: $todo.scheduledDate,
                        dueDate: $todo.dueDate,
                        isSomeday: $todo.isSomeday
                    )
                }

                Picker("Repeats", selection: $todo.recurrence) {
                    ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }

                if todo.recurrence != .none {
                    Toggle("Repeat after completion", isOn: $todo.repeatAfterCompletion)
                    if todo.recurrence == .custom {
                        Stepper(
                            "Every \(todo.customIntervalDays ?? 7) days",
                            value: Binding(
                                get: { todo.customIntervalDays ?? 7 },
                                set: { todo.customIntervalDays = $0 }
                            ),
                            in: 1...365
                        )
                    }
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
        .onChange(of: todo.title) { _, _ in saveTodoChanges() }
        .onChange(of: todo.notes) { _, _ in saveTodoChanges() }
        .onChange(of: todo.dueDate) { _, _ in saveTodoChanges() }
        .onChange(of: todo.priority) { _, _ in saveTodoChanges() }
        .onChange(of: todo.tags) { _, _ in saveTodoChanges() }
        .onChange(of: todo.isCompleted) { _, _ in saveTodoChanges() }
        .onDisappear {
            saveTodoChanges()
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

    private func saveTodoChanges() {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save todo changes: \(error)")
        }
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    @State private var isShowingCustomTagSheet = false
    @State private var searchText = ""
    @State private var pendingNewTagName = ""
    @State private var pendingTagColor: TagColor = .blue
    @State private var editingOriginalTag: String?
    @FocusState private var isSearchFieldFocused: Bool
    
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
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        createTagFromSearchIfNeeded()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(.systemGray6))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Student tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredStudentTags, id: \.self) { tag in
                        TagButton(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onToggle: { toggleTag(tag) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }

            // Previously used non-student tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredUsedTags, id: \.self) { tag in
                        TagButton(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onToggle: { toggleTag(tag) },
                            onEdit: { beginEditing(tag: tag) }
                        )
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
                            .contextMenu {
                                if !TodoTagHelper.isStudentTag(tag) {
                                    Button("Edit Tag") {
                                        beginEditing(tag: tag)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingCustomTagSheet, onDismiss: {
            pendingNewTagName = ""
            pendingTagColor = .blue
            editingOriginalTag = nil
        }) {
            CustomTagSheet(
                selectedTags: $selectedTags,
                initialName: pendingNewTagName,
                initialColor: pendingTagColor,
                isEditing: editingOriginalTag != nil,
                onSave: { savedTag in
                    handleSavedTag(savedTag)
                }
            )
        }
        #if os(macOS)
        .onExitCommand {
            searchText = ""
            isSearchFieldFocused = true
        }
        #endif
    }
    
    private var usedNonStudentTags: [String] {
        let tags = Set(
            allTodos
                .flatMap(\.tags)
                .filter { !TodoTagHelper.isStudentTag($0) }
        )
        return tags.sorted {
            TodoTagHelper.tagName($0).localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
    }

    private var filteredUsedTags: [String] {
        guard !searchText.isEmpty else { return usedNonStudentTags }
        return usedNonStudentTags.filter {
            TodoTagHelper.tagName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredStudentTags: [String] {
        let tags = students.map { TodoTagHelper.createStudentTag(name: $0.fullName) }
        guard !searchText.isEmpty else { return tags }
        return tags.filter {
            TodoTagHelper.leafTagName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasSearchResults: Bool {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return !filteredStudentTags.isEmpty || !filteredUsedTags.isEmpty
    }
    
    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }

    private func createTagFromSearchIfNeeded() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard hasSearchResults == false else { return }
        editingOriginalTag = nil
        pendingNewTagName = trimmed
        pendingTagColor = .blue
        isShowingCustomTagSheet = true
    }

    private func beginEditing(tag: String) {
        guard !TodoTagHelper.isStudentTag(tag) else { return }
        editingOriginalTag = tag
        pendingNewTagName = TodoTagHelper.tagName(tag)
        pendingTagColor = TodoTagHelper.tagColor(tag)
        isShowingCustomTagSheet = true
    }

    private func handleSavedTag(_ savedTag: String) {
        if let originalTag = editingOriginalTag {
            selectedTags = uniqueTags(selectedTags.map { $0 == originalTag ? savedTag : $0 })

            for todo in allTodos where todo.tags.contains(originalTag) {
                let updated = todo.tags.map { $0 == originalTag ? savedTag : $0 }
                todo.tags = uniqueTags(updated)
            }

            do {
                try modelContext.save()
            } catch {
                print("⚠️ [\(#function)] Failed to save tag edit: \(error)")
            }
        } else if selectedTags.contains(savedTag) == false {
            selectedTags.append(savedTag)
        }
    }

    private func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    let onToggle: () -> Void
    var onEdit: (() -> Void)? = nil
    
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
        .contextMenu {
            if let onEdit {
                Button("Edit Tag") {
                    onEdit()
                }
            }
        }
    }
}

struct CustomTagSheet: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var tagName: String
    @State private var selectedColor: TagColor
    let isEditing: Bool
    let onSave: ((String) -> Void)?

    init(
        selectedTags: Binding<[String]>,
        initialName: String = "",
        initialColor: TagColor = .blue,
        isEditing: Bool = false,
        onSave: ((String) -> Void)? = nil
    ) {
        self._selectedTags = selectedTags
        self._tagName = State(initialValue: initialName)
        self._selectedColor = State(initialValue: initialColor)
        self.isEditing = isEditing
        self.onSave = onSave
    }
    
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
            .navigationTitle(isEditing ? "Edit Tag" : "New Tag")
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
                    Button(isEditing ? "Save" : "Add") {
                        let tag = TodoTagHelper.createTag(name: tagName, color: selectedColor)
                        if let onSave {
                            onSave(tag)
                        } else if selectedTags.contains(tag) == false {
                            selectedTags.append(tag)
                        }
                        dismiss()
                    }
                    .disabled(tagName.isEmpty)
                }
            }
        }
    }
}

// MARK: - TodoItem Extension


