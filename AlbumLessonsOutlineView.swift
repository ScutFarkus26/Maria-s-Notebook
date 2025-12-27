import SwiftUI
import SwiftData

public struct AlbumLessonsOutlineView: View {
    // Optional scope (subject). If nil, user can pick a subject at top.
    var scopeKey: String?

    @Environment(\.modelContext) private var modelContext

    // Fetch all lessons; we'll filter in-memory to keep logic simple and avoid complex predicates.
    @Query private var allLessons: [Lesson]

    // UI State
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var selectedLessonID: UUID? = nil
    @State private var renameTargetGroup: String? = nil
    @State private var renameNewName: String = ""
    @State private var showingRenameSheet: Bool = false

    @State private var showingAddGroupSheet: Bool = false
    @State private var newGroupName: String = ""

    @State private var localScopeKey: String? = nil

    public init(scopeKey: String? = nil) {
        self.scopeKey = scopeKey
    }

    private var albumLessons: [Lesson] {
        allLessons.filter { $0.source == .album }
    }

    private var effectiveScopeKey: String? {
        localScopeKey ?? scopeKey
    }

    private var availableSubjects: [String] {
        let set = Set(albumLessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Group Computation
    private struct GroupInfo: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var sortIndex: Int
        var isCollapsed: Bool
    }

    private enum OutlineRow: Identifiable, Equatable {
        case groupHeader(groupName: String)
        case lessonRow(id: UUID, groupName: String)

        var id: String {
            switch self {
            case .groupHeader(let g): return "g::\(g)"
            case .lessonRow(let id, _): return "l::\(id.uuidString)"
            }
        }
    }

    private var scopedLessons: [Lesson] {
        guard let key = effectiveScopeKey, !key.isEmpty else { return albumLessons }
        return albumLessons.filter { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(key) == .orderedSame }
    }

    private var groupNamesInScope: [String] {
        // Include empty string for ungrouped if present
        var set = Set(scopedLessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) })
        if set.contains("") == false {
            // only include ungrouped when at least one lesson is ungrouped
            // set already includes groups from lessons; nothing else to add
        }
        return Array(set)
    }

    @MainActor
    private func fetchOrders(for scope: String) -> [AlbumGroupOrder] {
        let descriptor = FetchDescriptor<AlbumGroupOrder>()
        let all: [AlbumGroupOrder] = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.scopeKey.caseInsensitiveCompare(scope) == .orderedSame }
    }

    @MainActor
    private func fetchUIStates(for scope: String) -> [AlbumGroupUIState] {
        let descriptor = FetchDescriptor<AlbumGroupUIState>()
        let all: [AlbumGroupUIState] = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.scopeKey.caseInsensitiveCompare(scope) == .orderedSame }
    }

    @MainActor
    private func groupOrder(for scope: String) -> [GroupInfo] {
        // Compute named groups in this scope (exclude empty string for FilterOrderStore)
        let namedSet = Set(scopedLessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let existingNamed = Array(namedSet).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        // Ask FilterOrderStore for the user-preferred order used by the Lessons view
        let orderedNamed = FilterOrderStore.loadGroupOrder(for: scope, existing: existingNamed)

        let states = fetchUIStates(for: scope)

        var infos: [GroupInfo] = []
        for (idx, name) in orderedNamed.enumerated() {
            let collapsed = states.first { $0.groupName.caseInsensitiveCompare(name) == .orderedSame }?.isCollapsed ?? false
            infos.append(GroupInfo(name: name, sortIndex: idx, isCollapsed: collapsed))
        }

        // If there are any ungrouped lessons (empty group), append it after named groups
        let hasUngrouped = scopedLessons.contains { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasUngrouped {
            let collapsed = states.first { $0.groupName.isEmpty }?.isCollapsed ?? false
            infos.append(GroupInfo(name: "", sortIndex: infos.count, isCollapsed: collapsed))
        }

        return infos
    }

    @MainActor
    private func lessons(in group: String) -> [Lesson] {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = scopedLessons.filter { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame }
        // Ensure orderInGroup has sensible values and sort
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted
    }

    @MainActor
    private func buildRows(scope: String) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        let groups = groupOrder(for: scope)
        for g in groups {
            rows.append(.groupHeader(groupName: g.name))
            if !g.isCollapsed {
                for l in lessons(in: g.name) {
                    rows.append(.lessonRow(id: l.id, groupName: g.name))
                }
            }
        }
        return rows
    }

    @ViewBuilder
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if scopeKey == nil {
                    // Picker to choose subject scope when not provided
                    HStack(spacing: 12) {
                        Text("Subject:")
                        Picker("Subject", selection: Binding(
                            get: { self.effectiveScopeKey ?? availableSubjects.first },
                            set: { self.localScopeKey = $0 }
                        )) {
                            ForEach(availableSubjects, id: \.self) { s in
                                Text(s).tag(Optional(s))
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                    }
                    .padding(12)
                }

                if let scope = effectiveScopeKey ?? availableSubjects.first {
                    let rows = buildRows(scope: scope)
                    List {
                        ForEach(rows) { row in
                            switch row {
                            case .groupHeader(let groupName):
                                groupHeaderRow(scope: scope, groupName: groupName)
                            case .lessonRow(let id, let groupName):
                                if let lesson = scopedLessons.first(where: { $0.id == id }) {
                                    lessonRow(lesson: lesson, groupName: groupName)
                                }
                            }
                        }
                        .onMove { indices, newOffset in
                            handleMove(scope: scope, rows: rows, indices: indices, newOffset: newOffset)
                        }
                    }
                    #if os(iOS)
                    .environment(\.editMode, $editMode)
                    #endif
                    .navigationTitle("Album Lessons (Outline)")
                    .toolbar { outlineToolbar(scope: scope) }
                    .sheet(isPresented: $showingRenameSheet) { renameSheet(scope: scope) }
                    .sheet(isPresented: $showingAddGroupSheet) { addGroupSheet(scope: scope) }
                } else {
                    ContentUnavailableView("No Album Lessons", systemImage: "text.book.closed", description: Text("Add lessons to begin."))
                }
            }
        }
    }

    // MARK: - Rows
    private func groupHeaderRow(scope: String, groupName: String) -> some View {
        let display = AlbumGroupOrder.displayName(for: groupName)
        let isCollapsed = isGroupCollapsed(scope: scope, groupName: groupName)
        return HStack(spacing: 8) {
            Button {
                toggleGroupCollapsed(scope: scope, groupName: groupName)
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.easeInOut(duration: 0.15), value: isCollapsed)
            }
            .buttonStyle(.plain)

            Text(display)
                .font(.headline)
                .contextMenu {
                    Button("Rename…") { beginRename(scope: scope, groupName: groupName) }
                    Button("Add Group…") { showingAddGroupSheet = true }
                    Button("Delete Group", role: .destructive) { deleteGroup(scope: scope, groupName: groupName) }
                }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func lessonRow(lesson: Lesson, groupName: String) -> some View {
        let isSelected = selectedLessonID == lesson.id
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.body)
                if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                    Text(subtitle(for: lesson))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture { selectedLessonID = lesson.id }
        .contextMenu {
            Button("Indent") { indent(lesson: lesson) }
            Button("Outdent") { outdent(lesson: lesson) }
        }
    }

    private func subtitle(for lesson: Lesson) -> String {
        switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
        case (false, false): return "\(lesson.subject) • \(lesson.group)"
        case (false, true): return lesson.subject
        case (true, false): return lesson.group
        default: return ""
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private func outlineToolbar(scope: String) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            EditButton()
            #endif
            Button { showingAddGroupSheet = true } label: { Label("+ Group", systemImage: "plus") }
            Button { if let id = selectedLessonID, let l = scopedLessons.first(where: { $0.id == id }) { indent(lesson: l) } } label: { Label("Indent", systemImage: "arrow.right.to.line") }
                .disabled(selectedLessonID == nil)
            Button { if let id = selectedLessonID, let l = scopedLessons.first(where: { $0.id == id }) { outdent(lesson: l) } } label: { Label("Outdent", systemImage: "arrow.left.to.line") }
                .disabled(selectedLessonID == nil)
            Button { setAllCollapsed(scope: scope, collapsed: false) } label: { Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left") }
            Button { setAllCollapsed(scope: scope, collapsed: true) } label: { Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
    }

    // MARK: - Sheets
    private func renameSheet(scope: String) -> some View {
        NavigationStack {
            Form {
                Section(header: Text("Rename Group")) {
                    TextField("New Name", text: $renameNewName)
                }
            }
            .navigationTitle(AlbumGroupOrder.displayName(for: renameTargetGroup ?? ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingRenameSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let old = renameTargetGroup { applyRename(scope: scope, oldName: old, newName: renameNewName) }
                        showingRenameSheet = false
                    }
                    .disabled(renameNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 160)
        .presentationSizing(.fitted)
        #endif
    }

    private func addGroupSheet(scope: String) -> some View {
        NavigationStack {
            Form {
                Section(header: Text("New Group")) {
                    TextField("Group Name", text: $newGroupName)
                }
            }
            .navigationTitle("Add Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddGroupSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addGroup(scope: scope, name: newGroupName); showingAddGroupSheet = false }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 140)
        .presentationSizing(.fitted)
        #endif
    }

    // MARK: - Actions
    private func beginRename(scope: String, groupName: String) {
        renameTargetGroup = groupName
        renameNewName = groupName
        showingRenameSheet = true
    }

    @MainActor
    private func addGroup(scope: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existingOrders = fetchOrders(for: scope)
        if existingOrders.contains(where: { $0.groupName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // Already exists; nothing to do
            return
        }
        let maxIndex = (existingOrders.map { $0.sortIndex }.max() ?? -1)
        let order = AlbumGroupOrder(scopeKey: scope, groupName: trimmed, sortIndex: maxIndex + 1)
        let state = AlbumGroupUIState(scopeKey: scope, groupName: trimmed, isCollapsed: false)
        modelContext.insert(order)
        modelContext.insert(state)
        try? modelContext.save()

        // Also persist to FilterOrderStore used by Lessons view
        let namedSet = Set(scopedLessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var ordered = FilterOrderStore.loadGroupOrder(for: scope, existing: Array(namedSet))
        if !ordered.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            ordered.append(trimmed)
            FilterOrderStore.saveGroupOrder(ordered, for: scope)
        }

        newGroupName = ""
    }

    @MainActor
    private func deleteGroup(scope: String, groupName: String) {
        // Only delete records if the group has no lessons
        let hasLessons = !lessons(in: groupName).isEmpty
        guard !hasLessons else { return }
        let orders = fetchOrders(for: scope)
        let states = fetchUIStates(for: scope)
        for o in orders where o.groupName == groupName { modelContext.delete(o) }
        for s in states where s.groupName == groupName { modelContext.delete(s) }
        try? modelContext.save()

        // Remove from FilterOrderStore order as well
        let namedSetAfter = Set(scopedLessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let orderedAfter = FilterOrderStore.loadGroupOrder(for: scope, existing: Array(namedSetAfter))
        FilterOrderStore.saveGroupOrder(orderedAfter, for: scope)
    }

    @MainActor
    private func applyRename(scope: String, oldName: String, newName raw: String) {
        let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard oldName.caseInsensitiveCompare(newName) != .orderedSame else { return }
        // Merge if destination exists
        let orders = fetchOrders(for: scope)
        let states = fetchUIStates(for: scope)
        let destExists = orders.contains { $0.groupName.caseInsensitiveCompare(newName) == .orderedSame }
        // Update lessons
        let sourceLessons = lessons(in: oldName)
        if destExists {
            // Move lessons into the existing group
            for l in sourceLessons { l.group = newName }
            renumberGroup(scope: scope, groupName: newName)
            renumberGroup(scope: scope, groupName: oldName)
            // Remove old order/state records
            for o in orders where o.groupName.caseInsensitiveCompare(oldName) == .orderedSame { modelContext.delete(o) }
            for s in states where s.groupName.caseInsensitiveCompare(oldName) == .orderedSame { modelContext.delete(s) }
        } else {
            // Update records and lessons in place
            for l in sourceLessons { l.group = newName }
            for o in orders where o.groupName.caseInsensitiveCompare(oldName) == .orderedSame { o.groupName = newName }
            for s in states where s.groupName.caseInsensitiveCompare(oldName) == .orderedSame { s.groupName = newName }
            renumberGroup(scope: scope, groupName: newName)
        }
        try? modelContext.save()

        // Mirror rename into FilterOrderStore order used by Lessons view
        var namedSet = Set(scopedLessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNew.isEmpty { namedSet.insert(trimmedNew) }
        var order = FilterOrderStore.loadGroupOrder(for: scope, existing: Array(namedSet))
        let newExistsInOrder = order.contains { $0.caseInsensitiveCompare(newName) == .orderedSame }
        var updated: [String] = []
        updated.reserveCapacity(order.count)
        for g in order {
            if g.caseInsensitiveCompare(oldName) == .orderedSame {
                if !newExistsInOrder && !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated.append(newName)
                } // else: merging into existing group, drop the old entry
            } else {
                updated.append(g)
            }
        }
        FilterOrderStore.saveGroupOrder(updated, for: scope)
    }

    @MainActor
    private func setAllCollapsed(scope: String, collapsed: Bool) {
        // Consider all known groups in this scope (from lessons) plus any in the order table
        let orders = fetchOrders(for: scope)
        var states = fetchUIStates(for: scope)
        var allGroupNames = Set(groupNamesInScope)
        for o in orders { allGroupNames.insert(o.groupName) }
        for name in allGroupNames {
            if let idx = states.firstIndex(where: { $0.groupName.caseInsensitiveCompare(name) == .orderedSame }) {
                states[idx].isCollapsed = collapsed
            } else {
                let s = AlbumGroupUIState(scopeKey: scope, groupName: name, isCollapsed: collapsed)
                modelContext.insert(s)
                states.append(s)
            }
        }
        try? modelContext.save()
    }

    @MainActor
    private func toggleGroupCollapsed(scope: String, groupName: String) {
        var states = fetchUIStates(for: scope)
        if let s = states.first(where: { $0.groupName.caseInsensitiveCompare(groupName) == .orderedSame }) {
            s.isCollapsed.toggle()
        } else {
            let s = AlbumGroupUIState(scopeKey: scope, groupName: groupName, isCollapsed: true)
            modelContext.insert(s)
        }
        try? modelContext.save()
    }

    private func isGroupCollapsed(scope: String, groupName: String) -> Bool {
        let states = fetchUIStates(for: scope)
        return states.first(where: { $0.groupName.caseInsensitiveCompare(groupName) == .orderedSame })?.isCollapsed ?? false
    }

    // MARK: - Move Handling
    @MainActor
    private func handleMove(scope: String, rows: [OutlineRow], indices: IndexSet, newOffset: Int) {
        // Determine if moving groups only
        let moving = indices.map { rows[$0] }
        let movingIsAllGroups = moving.allSatisfy { if case .groupHeader = $0 { return true } else { return false } }
        if movingIsAllGroups {
            reorderGroups(scope: scope, rows: rows, indices: indices, newOffset: newOffset)
            return
        }
        // Lessons move within same group only
        let lessonRows = moving.compactMap { row -> (UUID, String)? in
            if case let .lessonRow(id, groupName) = row { return (id, groupName) }
            return nil
        }
        guard !lessonRows.isEmpty else { return }
        let uniqueGroups = Set(lessonRows.map { $0.1 })
        guard uniqueGroups.count == 1, let groupName = uniqueGroups.first else { return }
        reorderLessonsWithinGroup(scope: scope, groupName: groupName, rows: rows, indices: indices, newOffset: newOffset)
    }

    @MainActor
    private func reorderGroups(scope: String, rows: [OutlineRow], indices: IndexSet, newOffset: Int) {
        // Build current group order from visible rows
        var groupOrderRows: [String] = rows.compactMap { row in
            if case let .groupHeader(g) = row { return g } else { return nil }
        }
        // Move the selected groups
        let movingNames: [String] = indices.sorted().compactMap { idx in
            if case let .groupHeader(g) = rows[idx] { return g } else { return nil }
        }
        // Remove moving
        for g in movingNames { if let i = groupOrderRows.firstIndex(of: g) { groupOrderRows.remove(at: i) } }
        // Compute insertion index within group headers
        let destWithinHeaders = min(max(newOffset - indices.filter { $0 < newOffset }.count, 0), groupOrderRows.count)
        groupOrderRows.insert(contentsOf: movingNames, at: destWithinHeaders)

        // Persist to FilterOrderStore (named groups only)
        let namedOnly = groupOrderRows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        FilterOrderStore.saveGroupOrder(namedOnly, for: scope)

        // Persist new sortIndex sequence
        let orders = fetchOrders(for: scope)
        // Ensure an order record exists for each group
        var orderMap: [String: AlbumGroupOrder] = [:]
        for g in groupOrderRows {
            if let existing = orders.first(where: { $0.groupName.caseInsensitiveCompare(g) == .orderedSame }) {
                orderMap[g] = existing
            } else {
                let o = AlbumGroupOrder(scopeKey: scope, groupName: g, sortIndex: 0)
                modelContext.insert(o)
                orderMap[g] = o
            }
        }
        for (idx, g) in groupOrderRows.enumerated() {
            orderMap[g]?.sortIndex = idx
        }
        try? modelContext.save()
    }

    @MainActor
    private func reorderLessonsWithinGroup(scope: String, groupName: String, rows: [OutlineRow], indices: IndexSet, newOffset: Int) {
        // Build current visible lesson sequence for this group
        let currentLessons: [Lesson] = lessons(in: groupName)
        var ids: [UUID] = currentLessons.map { $0.id }
        let movingIDs: [UUID] = indices.sorted().compactMap { idx in
            if case let .lessonRow(id, g) = rows[idx], g.caseInsensitiveCompare(groupName) == .orderedSame { return id } else { return nil }
        }
        // Remove moving IDs
        ids.removeAll(where: { movingIDs.contains($0) })
        // Compute destination within this group's lessons
        // Find the number of lesson rows before newOffset that belong to this group
        let prefix = rows.prefix(newOffset)
        let destCountInGroup = prefix.reduce(0) { acc, row in
            if case let .lessonRow(_, g) = row, g.caseInsensitiveCompare(groupName) == .orderedSame { return acc + 1 }
            else { return acc }
        }
        let clampedDest = min(max(destCountInGroup, 0), ids.count)
        ids.insert(contentsOf: movingIDs, at: clampedDest)
        // Persist new orderInGroup 1..N
        var map: [UUID: Lesson] = Dictionary(uniqueKeysWithValues: currentLessons.map { ($0.id, $0) })
        for (idx, id) in ids.enumerated() {
            map[id]?.orderInGroup = idx + 1
        }
        try? modelContext.save()
    }

    // MARK: - Indent/Outdent
    @MainActor
    private func indent(lesson: Lesson) {
        guard let scope = effectiveScopeKey ?? availableSubjects.first else { return }
        let groups = groupOrder(for: scope)
        guard let currentIdx = groups.firstIndex(where: { $0.name.caseInsensitiveCompare(lesson.group) == .orderedSame }) else { return }
        let targetIdx = currentIdx - 1
        guard targetIdx >= 0 else { return }
        move(lesson: lesson, toGroup: groups[targetIdx].name, scope: scope)
    }

    @MainActor
    private func outdent(lesson: Lesson) {
        guard let scope = effectiveScopeKey ?? availableSubjects.first else { return }
        let groups = groupOrder(for: scope)
        guard let currentIdx = groups.firstIndex(where: { $0.name.caseInsensitiveCompare(lesson.group) == .orderedSame }) else { return }
        let targetIdx = currentIdx + 1
        guard targetIdx < groups.count else { return }
        move(lesson: lesson, toGroup: groups[targetIdx].name, scope: scope)
    }

    @MainActor
    private func move(lesson: Lesson, toGroup: String, scope: String) {
        let src = lesson.group
        if src.caseInsensitiveCompare(toGroup) == .orderedSame { return }
        // Append to end of destination group
        let destLessons = lessons(in: toGroup)
        let newOrder = (destLessons.map { $0.orderInGroup }.max() ?? 0) + 1
        lesson.group = toGroup
        lesson.orderInGroup = newOrder
        // Renumber both groups for stability
        renumberGroup(scope: scope, groupName: src)
        renumberGroup(scope: scope, groupName: toGroup)
        try? modelContext.save()
        selectedLessonID = lesson.id
    }

    @MainActor
    private func renumberGroup(scope: String, groupName: String) {
        let list = lessons(in: groupName)
        for (idx, l) in list.enumerated() { l.orderInGroup = idx + 1 }
    }
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let samples: [Lesson] = [
        Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "", writeUp: ""),
        Lesson(name: "Bead Frame", subject: "Math", group: "Number Work", subheading: "", writeUp: ""),
        Lesson(name: "Stamp Game", subject: "Math", group: "Operations", subheading: "", writeUp: ""),
        Lesson(name: "Noun", subject: "Language", group: "Grammar", subheading: "", writeUp: "")
    ]
    for l in samples { l.source = .album; ctx.insert(l) }
    return NavigationStack {
        AlbumLessonsOutlineView()
            .previewEnvironment(using: container)
    }
}

