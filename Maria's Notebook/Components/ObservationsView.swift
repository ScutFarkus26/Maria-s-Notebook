import SwiftUI
import SwiftData

struct ObservationsView: View {
    @Environment(\.modelContext) private var modelContext

    // Composer
    @State private var isShowingComposer = false

    // Loaded pages (unfiltered)
    @State private var loadedNotes: [Note] = []
    @State private var isLoading: Bool = false
    @State private var hasMore: Bool = true
    @State private var lastCursorDate: Date? = nil // fetch notes where createdAt < lastCursorDate

    // Filters (applied in-memory)
    enum ScopeFilter: String, CaseIterable, Identifiable { case all = "All", studentSpecific = "Student-specific", allStudents = "All students"; var id: String { rawValue } }
    @State private var selectedCategory: NoteCategory? = nil
    @State private var selectedScope: ScopeFilter = .all
    @State private var searchText: String = ""
    @State private var noteBeingEdited: Note? = nil

    // Lookup cache for student names shown on rows
    @State private var studentsByID: [UUID: Student] = [:]

    private let pageSize: Int = 50

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                // Filters
                filterBar
                
                // List
                List {
                    if filteredNotes.isEmpty, !isLoading {
                        ContentUnavailableView("No observations", systemImage: "note.text")
                            .listRowBackground(Color.clear)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredNotes, id: \.id) { note in
                            row(for: note)
                        }
                        if hasMore {
                            loadMoreRow
                        }
                    }
                }
                .listStyle(.inset)
            }
            .navigationTitle("Observations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingComposer = true
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .onAppear { loadFirstPageIfNeeded() }
        .onChange(of: loadedNotes.map { $0.id }) { _, _ in
            loadStudentsIfNeeded(for: filteredNotes)
        }
        .onChange(of: selectedCategory) { _, _ in
            // Category is filtered in-memory; keep pages as-is
            loadStudentsIfNeeded(for: filteredNotes)
        }
        .onChange(of: selectedScope) { _, _ in
            loadStudentsIfNeeded(for: filteredNotes)
        }
        .onChange(of: searchText) { _, _ in
            loadStudentsIfNeeded(for: filteredNotes)
        }
        .sheet(isPresented: $isShowingComposer) {
            QuickNoteSheet()
        }
        .sheet(item: $noteBeingEdited) { note in
            NoteEditSheet(note: note)
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            .presentationSizingFitted()
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
    }

    // MARK: - Filters UI

    private var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Categories") { selectedCategory = nil }
                Divider()
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    Button(action: { selectedCategory = cat }) {
                        Label(cat.rawValue.capitalized, systemImage: selectedCategory == cat ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedCategoryLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Menu {
                ForEach(ScopeFilter.allCases) { sf in
                    Button(action: { selectedScope = sf }) {
                        Label(sf.rawValue, systemImage: selectedScope == sf ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedScope.rawValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var selectedCategoryLabel: String {
        if let cat = selectedCategory { return cat.rawValue.capitalized }
        return "All Categories"
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.tint)
                Text(note.category.rawValue.capitalized)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(note.createdAt, style: .relative)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let firstLine = firstLine(of: note.body) {
                Text(firstLine)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            let ids = studentIDs(for: note)
            if !ids.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ids.prefix(3), id: \.self) { sid in
                            if let s = studentsByID[sid] {
                                studentChip(displayName(for: s))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    #endif
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }

    private func studentChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }

    private func firstLine(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let newline = trimmed.firstIndex(of: "\n") {
            return String(trimmed[..<newline])
        }
        return trimmed
    }

    // MARK: - Data

    private var filteredNotes: [Note] {
        var result = loadedNotes
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        switch selectedScope {
        case .all: break
        case .studentSpecific:
            result = result.filter { scopeIsStudentSpecific($0.scope) }
        case .allStudents:
            result = result.filter { scopeIsAllStudents($0.scope) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.body.localizedCaseInsensitiveContains(query) }
        }
        return result
    }

    private func loadFirstPageIfNeeded() {
        if loadedNotes.isEmpty && !isLoading {
            Task { await loadNextPage() }
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetch: FetchDescriptor<Note>
            if let cutoff = lastCursorDate {
                var tmp = FetchDescriptor<Note>(
                    predicate: #Predicate { $0.createdAt < cutoff },
                    sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
                )
                tmp.fetchLimit = pageSize
                fetch = tmp
            } else {
                var tmp = FetchDescriptor<Note>(
                    predicate: nil,
                    sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
                )
                tmp.fetchLimit = pageSize
                fetch = tmp
            }
            let page = try modelContext.fetch(fetch)
            if page.isEmpty { hasMore = false }
            loadedNotes.append(contentsOf: page)
            if let minDate = page.map(\.createdAt).min() {
                lastCursorDate = minDate
            } else {
                hasMore = false
            }
            // Preload student names for visible notes
            loadStudentsIfNeeded(for: filteredNotes)
        } catch {
            hasMore = false
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().padding(.vertical, 8)
            } else {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    Label("Load More", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private func scopeIsStudentSpecific(_ scope: NoteScope) -> Bool {
        switch scope {
        case .all: return false
        case .student, .students: return true
        }
    }

    private func scopeIsAllStudents(_ scope: NoteScope) -> Bool {
        switch scope {
        case .all: return true
        case .student, .students: return false
        }
    }

    private func studentIDs(for note: Note) -> [UUID] {
        switch note.scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
        }
    }

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = student.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    @MainActor
    private func loadStudentsIfNeeded(for notes: [Note]) {
        let idsNeeded = Set(notes.flatMap { studentIDs(for: $0) })
        let missing = idsNeeded.filter { studentsByID[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let descriptor = FetchDescriptor<Student>(predicate: #Predicate { missing.contains($0.id) })
            let fetched = try modelContext.fetch(descriptor)
            for s in fetched { studentsByID[s.id] = s }
        } catch {
            // Fallback: no-op on error
        }
    }
}

