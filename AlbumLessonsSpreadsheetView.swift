import SwiftUI
import SwiftData

struct AlbumLessonsSpreadsheetView: View {
    // Optional preselected subject filter
    var subjectFilter: String?

    @Environment(\.modelContext) private var modelContext

    // Fetch all lessons, then filter down to album lessons in-memory to keep UI responsive
    @Query private var allLessons: [Lesson]

    // Local UI state
    @State private var searchText: String = ""
    @State private var selectedSubject: String? = nil

    // Cross-platform selection of rows (by Lesson.id)
    @State private var selection: Set<UUID> = []

    // Sorting
    enum Column: String, CaseIterable, Identifiable { case name, subject, group, order; var id: String { rawValue } }
    @State private var sortColumn: Column = .subject
    @State private var sortAscending: Bool = true

    // Batch Edit
    @State private var showingBatchEdit: Bool = false
    @State private var batchGroup: String = ""
    @State private var batchSubject: String = ""

    // Renumber
    private enum RenumberBasis: String, CaseIterable, Identifiable { case currentSort = "Current Sort", name = "Name"; var id: String { rawValue } }
    @State private var showingRenumber: Bool = false
    @State private var renumberGroupKey: String = "(All)"
    @State private var renumberBasis: RenumberBasis = .currentSort

    private let lessonsVM = LessonsViewModel()

    init(subjectFilter: String? = nil) {
        self.subjectFilter = subjectFilter?.trimmingCharacters(in: .whitespacesAndNewlines)
        _selectedSubject = State(initialValue: self.subjectFilter)
    }

    // MARK: - Derived Collections
    private var albumLessons: [Lesson] {
        allLessons.filter { $0.source == .album }
    }

    private var availableSubjects: [String] {
        lessonsVM.subjects(from: albumLessons)
    }

    private var filteredLessonsBase: [Lesson] {
        var base = albumLessons
        if let s = selectedSubject, !s.isEmpty {
            base = base.filter { $0.subject.caseInsensitiveCompare(s) == .orderedSame }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            base = base.filter { l in
                l.name.localizedCaseInsensitiveContains(q) ||
                l.subject.localizedCaseInsensitiveContains(q) ||
                l.group.localizedCaseInsensitiveContains(q)
            }
        }
        return base
    }

    private var sortedLessons: [Lesson] {
        let base = filteredLessonsBase
        let sorted: [Lesson] = base.sorted { lhs, rhs in
            switch sortColumn {
            case .name:
                let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if cmp != .orderedSame { return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending) }
                return lhs.id.uuidString < rhs.id.uuidString
            case .subject:
                let cmp = lhs.subject.localizedCaseInsensitiveCompare(rhs.subject)
                if cmp != .orderedSame { return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending) }
                // Then group, then order, then name
                let gc = lhs.group.localizedCaseInsensitiveCompare(rhs.group)
                if gc != .orderedSame { return gc == .orderedAscending }
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .group:
                let cmp = lhs.group.localizedCaseInsensitiveCompare(rhs.group)
                if cmp != .orderedSame { return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending) }
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .order:
                if lhs.orderInGroup != rhs.orderInGroup { return sortAscending ? (lhs.orderInGroup < rhs.orderInGroup) : (lhs.orderInGroup > rhs.orderInGroup) }
                let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        return sorted
    }

    private var existingGroups: [String] {
        let set = Set(filteredLessonsBase.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) })
        return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Body
    var body: some View {
        content
            .navigationTitle("Edit Order (Spreadsheet)")
            .searchable(text: $searchText)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingBatchEdit) { batchEditSheet }
            .sheet(isPresented: $showingRenumber) { renumberSheet }
            .onChange(of: selectedSubject) { _, _ in selection.removeAll() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(spacing: 8) {
            controlsRow
            Table(sortedLessons, selection: $selection) {
                TableColumn("Name", value: \.name)
                TableColumn("Subject", value: \.subject)
                TableColumn("Group") { lesson in
                    groupEditor(for: lesson)
                }
                TableColumn("Group Order") { lesson in
                    orderEditor(for: lesson)
                }
                .width(80)
            }
        }
        .padding(12)
        #else
        VStack(spacing: 0) {
            controlsRow
            List(selection: $selection) {
                ForEach(sortedLessons, id: \.id) { lesson in
                    row(for: lesson)
                }
            }
            .environment(\.editMode, .constant(.active)) // allow multi-select with explicit EditButton too
        }
        #endif
    }

    // MARK: - Controls
    private var controlsRow: some View {
        HStack(spacing: 12) {
            // Subject filter
            Menu {
                Button("All Subjects") { selectedSubject = nil }
                ForEach(availableSubjects, id: \.self) { s in
                    Button(s) { selectedSubject = s }
                }
            } label: {
                Label(selectedSubject ?? "All Subjects", systemImage: "line.3.horizontal.decrease.circle")
            }

            Divider().frame(height: 16)

            // Sort controls
            Picker("Sort", selection: $sortColumn) {
                Text("Subject").tag(Column.subject)
                Text("Group").tag(Column.group)
                Text("Order").tag(Column.order)
                Text("Name").tag(Column.name)
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $sortAscending) { Image(systemName: sortAscending ? "arrow.up" : "arrow.down") }
                .toggleStyle(.button)
                .help("Toggle ascending/descending")

            Spacer()

            #if !os(macOS)
            EditButton()
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Row Builders
    private func row(for lesson: Lesson) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    if !lesson.subject.isEmpty {
                        Text(lesson.subject).font(.caption).foregroundStyle(.secondary)
                    }
                    if !lesson.group.isEmpty {
                        Text("•").foregroundStyle(.secondary).font(.caption)
                        Text(lesson.group).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            groupEditor(for: lesson)
            orderEditor(for: lesson)
        }
        .contentShape(Rectangle())
    }

    private func groupEditor(for lesson: Lesson) -> some View {
        let binding = Binding<String>(
            get: { lesson.group },
            set: { newValue in
                if lesson.group != newValue { lesson.group = newValue; saveContext(reason: "Update group") }
            }
        )
        return TextField("Group", text: binding)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120)
    }

    private func orderEditor(for lesson: Lesson) -> some View {
        let binding = Binding<String>(
            get: { String(lesson.orderInGroup) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed) {
                    if lesson.orderInGroup != val { lesson.orderInGroup = val; saveContext(reason: "Update order") }
                }
            }
        )
        return HStack(spacing: 4) {
            #if os(macOS)
            TextField("Order", text: binding)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
            #else
            TextField("Order", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
            #endif
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingRenumber = true
            } label: {
                Label("Renumber…", systemImage: "number")
            }
            .help("Renumber Group Order for a chosen group")

            Button {
                showingBatchEdit = true
                batchGroup = ""
                batchSubject = selectedSubject ?? ""
            } label: {
                Label("Batch Edit", systemImage: "square.and.pencil")
            }
            .disabled(selection.isEmpty)
        }
    }

    // MARK: - Sheets
    private var batchEditSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Apply to \(selection.count) lesson\(selection.count == 1 ? "" : "s")")) {
                    TextField("Set Group", text: $batchGroup)
                    if !availableSubjects.isEmpty {
                        Picker("Subject", selection: $batchSubject) {
                            Text("(No Change)").tag("")
                            ForEach(availableSubjects, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Batch Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingBatchEdit = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { applyBatchEdit() } }
            }
        }
    }

    private var renumberSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group")) {
                    Picker("Group", selection: $renumberGroupKey) {
                        Text("(All)").tag("(All)")
                        Text("(Blank)").tag("(Blank)")
                        ForEach(existingGroups, id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }
                }
                Section(header: Text("Basis")) {
                    Picker("Order By", selection: $renumberBasis) {
                        ForEach(RenumberBasis.allCases) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(footer: Text("Assigns 1…N to Group Order for lessons in the selected group.")) { EmptyView() }
            }
            .navigationTitle("Renumber")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingRenumber = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { applyRenumber() } }
            }
        }
    }

    // MARK: - Actions
    private func applyBatchEdit() {
        guard !selection.isEmpty else { showingBatchEdit = false; return }
        let ids = selection
        let newGroup = batchGroup // allow empty to clear
        let newSubject = batchSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        for l in albumLessons where ids.contains(l.id) {
            if !newGroup.isEmpty || batchGroup.isEmpty { l.group = newGroup }
            if !newSubject.isEmpty { l.subject = newSubject }
        }
        saveContext(reason: "Batch edit lessons")
        showingBatchEdit = false
    }

    private func applyRenumber() {
        let target: [Lesson]
        switch renumberGroupKey {
        case "(All)":
            target = filteredLessonsBase
        case "(Blank)":
            target = filteredLessonsBase.filter { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        default:
            let g = renumberGroupKey
            target = filteredLessonsBase.filter { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(g) == .orderedSame }
        }
        guard !target.isEmpty else { showingRenumber = false; return }
        let ordered: [Lesson]
        switch renumberBasis {
        case .currentSort:
            // Use current sorted order but filter down to target IDs to preserve grouping
            let idset = Set(target.map { $0.id })
            ordered = sortedLessons.filter { idset.contains($0.id) }
        case .name:
            ordered = target.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        for (idx, l) in ordered.enumerated() {
            let newVal = idx + 1 // 1…N
            if l.orderInGroup != newVal { l.orderInGroup = newVal }
        }
        saveContext(reason: "Renumber group order")
        showingRenumber = false
    }

    private func saveContext(reason: String) {
        do { try modelContext.save() } catch { /* ignore and rely on autosave */ }
    }
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let samples: [Lesson] = [
        Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "", writeUp: ""),
        Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "", writeUp: "")
    ]
    for l in samples { l.source = .album; ctx.insert(l) }
    return NavigationStack {
        AlbumLessonsSpreadsheetView()
            .previewEnvironment(using: container)
    }
}
