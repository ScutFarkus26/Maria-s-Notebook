// swiftlint:disable file_length
// TodoMainView+Sidebar.swift
// Sidebar navigation for the todo list

import SwiftUI
import SwiftData

extension TodoMainView {
    // MARK: - Tag Data

    var allUsedTags: [String] {
        var tagSet = Set<String>()
        for todo in allTodos {
            for tag in todo.tags {
                tagSet.insert(tag)
            }
        }
        return tagSet.sorted {
            TodoTagHelper.tagName($0)
                .localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
    }

    /// All sidebar items (top-level tags + group names) in user-defined order.
    /// Items not yet in tagOrder are appended alphabetically.
    var orderedSidebarItems: [String] {
        // Collect unique sidebar entries: top-level tag strings and group folder names (prefixed with "folder:")
        var items: [String] = []
        var seen = Set<String>()

        for tag in allUsedTags {
            let components = TodoTagHelper.tagPathComponents(tag)
            if components.count <= 1 {
                // top-level tag
                if seen.insert(tag).inserted { items.append(tag) }
            } else {
                // nested -- represent folder by its root name
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
            // Both unknown -- fall back to alphabetical
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    func displayName(for sidebarItem: String) -> String {
        if sidebarItem.hasPrefix("folder:") {
            return String(sidebarItem.dropFirst("folder:".count))
        }
        return TodoTagHelper.tagName(sidebarItem)
    }

    var topLevelTags: [String] {
        allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count <= 1 }
    }

    func nestedTags(forGroup group: String) -> [String] {
        let nested = allUsedTags.filter {
            TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == group
        }
        // Sort children by position in tagOrder, then alphabetically
        let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: tagOrder.enumerated().map { ($1, $0) })
        return nested.sorted { lhs, rhs in
            let lhsIdx = orderMap[lhs] ?? Int.max
            let rhsIdx = orderMap[rhs] ?? Int.max
            if lhsIdx != rhsIdx { return lhsIdx < rhsIdx }
            return TodoTagHelper.leafTagName(lhs)
                .localizedCaseInsensitiveCompare(TodoTagHelper.leafTagName(rhs)) == .orderedAscending
        }
    }

    var groupedNestedTags: [(group: String, tags: [String])] {
        let nested = allUsedTags.filter { TodoTagHelper.tagPathComponents($0).count > 1 }
        let grouped = Dictionary(grouping: nested, by: { TodoTagHelper.rootTagName($0) })
        return grouped
            .map { entry in
                let sortedTags = entry.value.sorted {
                    TodoTagHelper.leafTagName($0)
                        .localizedCaseInsensitiveCompare(TodoTagHelper.leafTagName($1)) == .orderedAscending
                }
                return (group: entry.key, tags: sortedTags)
            }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    func persistTagOrder() {
        UserDefaults.standard.set(tagOrder, forKey: UserDefaultsKeys.todoTagOrder)
    }

    func moveTag(from source: String, toAfter destination: String) {
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

    // MARK: - Sidebar View

    var sidebar: some View {
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
                                .background(
                                    filter.color.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )

                            Text(filter.title)
                                .font(AppTheme.ScaledFont.body)
                                .fontWeight(isActive ? .semibold : .regular)

                            Spacer()

                            if filter != .all {
                                let count = countForFilter(filter)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(AppTheme.ScaledFont.captionSemibold)
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
                                        .font(AppTheme.ScaledFont.bodySemibold)
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
                                    adaptiveWithAnimation(.snappy(duration: 0.2)) {
                                        if selectedFolder == groupName {
                                            // Deselect folder
                                            selectedFolder = nil
                                            selectedFilter = .inbox
                                        } else {
                                            // Select folder -- show all items with tags in this folder
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
                                            .font(AppTheme.ScaledFont.captionSemibold)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let dropped = items.first, dropped != item else { return false }
                                    adaptiveWithAnimation(.snappy(duration: 0.2)) {
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
                            .foregroundStyle(AppColors.destructive)
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

    func tagRow(tag: String, displayName: String, dotSize: CGFloat, fontSize: CGFloat, dragKey: String) -> some View {
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
                    .font(AppTheme.ScaledFont.captionSemibold)
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
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                moveTag(from: dropped, toAfter: dragKey)
            }
            return true
        }
    }

    // MARK: - New Folder Sheet

    var newFolderSheet: some View {
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

    // MARK: - Sidebar Helper Functions

    var hasUnusedTags: Bool {
        let activeTags = Set(allTodos.filter { !$0.isCompleted }.flatMap { $0.tags })
        let allTags = Set(allTodos.flatMap { $0.tags })
        return allTags.subtracting(activeTags).isEmpty == false
    }

    func removeUnusedTags() {
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
