import SwiftUI
import SwiftData

// Unified note item for displaying all note types
private struct UnifiedObservationItem: Identifiable {
    let id: UUID
    let date: Date
    let body: String
    let category: NoteCategory
    let includeInReport: Bool
    let imagePath: String?
    let contextText: String?
    let studentIDs: [UUID]
    
    // Source tracking for editing
    enum Source {
        case note(Note)
        case scopedNote(ScopedNote)
        case workNote(WorkNote)
        case meetingNote(MeetingNote)
    }
    let source: Source
}

struct ObservationsView: View {
    @Environment(\.modelContext) private var modelContext

    // Composer
    @State private var isShowingComposer = false

    // Loaded items (unfiltered) - now includes all note types
    @State private var loadedItems: [UnifiedObservationItem] = []
    @State private var isLoading: Bool = false
    @State private var hasMore: Bool = true
    @State private var lastCursorDate: Date? = nil // fetch notes where createdAt < lastCursorDate

    // Filters (applied in-memory)
    enum ScopeFilter: String, CaseIterable, Identifiable { case all = "All", studentSpecific = "Student-specific", allStudents = "All students"; var id: String { rawValue } }
    @State private var selectedCategory: NoteCategory? = nil
    @State private var selectedScope: ScopeFilter = .all
    @State private var searchText: String = ""
    @State private var noteBeingEdited: Note? = nil
    @State private var scopedNoteBeingEdited: ScopedNote? = nil
    @State private var workNoteBeingEdited: WorkNote? = nil
    @State private var meetingNoteBeingEdited: MeetingNote? = nil

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
                    if filteredItems.isEmpty, !isLoading {
                        ContentUnavailableView("No observations", systemImage: "note.text")
                            .listRowBackground(Color.clear)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredItems, id: \.id) { item in
                            row(for: item)
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
        .onChange(of: loadedItems.map { $0.id }) { _, _ in
            loadStudentsIfNeeded(for: filteredItems)
        }
        .onChange(of: selectedCategory) { _, _ in
            // Category is filtered in-memory; keep pages as-is
            loadStudentsIfNeeded(for: filteredItems)
        }
        .onChange(of: selectedScope) { _, _ in
            loadStudentsIfNeeded(for: filteredItems)
        }
        .onChange(of: searchText) { _, _ in
            loadStudentsIfNeeded(for: filteredItems)
        }
        .sheet(isPresented: $isShowingComposer) {
            QuickNoteSheet()
        }
        .sheet(item: $noteBeingEdited) { note in
            UnifiedNoteEditor(
                context: contextForNote(note),
                initialNote: note,
                onSave: { _ in
                    noteBeingEdited = nil
                    reloadAllNotes()
                },
                onCancel: {
                    noteBeingEdited = nil
                }
            )
        }
        .sheet(item: $scopedNoteBeingEdited) { scopedNote in
            LegacyNoteEditor(
                title: "Edit Note",
                text: scopedNote.body,
                onSave: { newText in
                    scopedNote.body = newText
                    try? modelContext.save()
                    scopedNoteBeingEdited = nil
                    reloadAllNotes()
                },
                onCancel: {
                    scopedNoteBeingEdited = nil
                }
            )
        }
        .sheet(item: $workNoteBeingEdited) { workNote in
            LegacyNoteEditor(
                title: "Edit Note",
                text: workNote.text,
                onSave: { newText in
                    workNote.text = newText
                    try? modelContext.save()
                    workNoteBeingEdited = nil
                    reloadAllNotes()
                },
                onCancel: {
                    workNoteBeingEdited = nil
                }
            )
        }
        .sheet(item: $meetingNoteBeingEdited) { meetingNote in
            LegacyNoteEditor(
                title: "Edit Meeting Note",
                text: meetingNote.content,
                onSave: { newText in
                    meetingNote.content = newText
                    try? modelContext.save()
                    meetingNoteBeingEdited = nil
                    reloadAllNotes()
                },
                onCancel: {
                    meetingNoteBeingEdited = nil
                }
            )
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
    private func row(for item: UnifiedObservationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.tint)
                Text(item.category.rawValue.capitalized)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                // Show context badge if note is attached to a specific entity
                if let contextText = item.contextText {
                    Text(contextText)
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                
                Spacer()
                Text(item.date, style: .relative)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let firstLine = firstLine(of: item.body) {
                Text(firstLine)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if !item.studentIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.studentIDs.prefix(3), id: \.self) { sid in
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
                editItem(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    #endif
        .contextMenu {
            Button {
                editItem(item)
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    private func editItem(_ item: UnifiedObservationItem) {
        switch item.source {
        case .note(let note):
            noteBeingEdited = note
        case .scopedNote(let scopedNote):
            scopedNoteBeingEdited = scopedNote
        case .workNote(let workNote):
            workNoteBeingEdited = workNote
        case .meetingNote(let meetingNote):
            meetingNoteBeingEdited = meetingNote
        }
    }
    
    private func contextText(for note: Note) -> String? {
        if let lesson = note.lesson {
            return "Lesson: \(lesson.name)"
        }
        if let work = note.work {
            return "Work: \(work.title)"
        }
        if note.studentLesson != nil {
            return "Presentation"
        }
        if note.presentation != nil {
            return "Presentation"
        }
        if note.workContract != nil {
            return "Work Contract"
        }
        if note.attendanceRecord != nil {
            return "Attendance"
        }
        if note.workCheckIn != nil {
            return "Check-In"
        }
        if note.workCompletionRecord != nil {
            return "Completion"
        }
        if note.workPlanItem != nil {
            return "Plan"
        }
        if note.studentMeeting != nil {
            return "Meeting"
        }
        if note.projectSession != nil {
            return "Session"
        }
        if let communityTopic = note.communityTopic {
            return "Topic: \(communityTopic.title)"
        }
        if note.reminder != nil {
            return "Reminder"
        }
        if note.schoolDayOverride != nil {
            return "Override"
        }
        return nil
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

    private var filteredItems: [UnifiedObservationItem] {
        var result = loadedItems
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        switch selectedScope {
        case .all: break
        case .studentSpecific:
            result = result.filter { !$0.studentIDs.isEmpty }
        case .allStudents:
            result = result.filter { $0.studentIDs.isEmpty }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.body.localizedCaseInsensitiveContains(query) }
        }
        return result
    }

    private func loadFirstPageIfNeeded() {
        if loadedItems.isEmpty && !isLoading {
            Task { await loadAllNotes() }
        }
    }
    
    private func reloadAllNotes() {
        loadedItems = []
        lastCursorDate = nil
        hasMore = true
        Task { await loadAllNotes() }
    }

    @MainActor
    private func loadAllNotes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        var allItems: [UnifiedObservationItem] = []
        
        // 1. Fetch all Note objects
        do {
            let noteFetch = FetchDescriptor<Note>(
                sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
            )
            let notes: [Note] = try modelContext.fetch(noteFetch)
            for note in notes {
                let studentIDs = studentIDsFromScope(note.scope)
                let context = contextText(for: note)
                allItems.append(UnifiedObservationItem(
                    id: note.id,
                    date: note.createdAt,
                    body: note.body,
                    category: note.category,
                    includeInReport: note.includeInReport,
                    imagePath: note.imagePath,
                    contextText: context,
                    studentIDs: studentIDs,
                    source: .note(note)
                ))
            }
        } catch {
            print("Error fetching Note objects: \(error)")
        }
        
        // 2. Fetch all ScopedNote objects
        do {
            let scopedFetch = FetchDescriptor<ScopedNote>(
                sortBy: [SortDescriptor(\ScopedNote.createdAt, order: .reverse)]
            )
            let scopedNotes: [ScopedNote] = try modelContext.fetch(scopedFetch)
            for scopedNote in scopedNotes {
                let studentIDs = studentIDsFromScopedNoteScope(scopedNote.scope)
                let context = contextTextForScopedNote(scopedNote)
                allItems.append(UnifiedObservationItem(
                    id: scopedNote.id,
                    date: scopedNote.createdAt,
                    body: scopedNote.body,
                    category: .general, // ScopedNote doesn't have category
                    includeInReport: false,
                    imagePath: nil,
                    contextText: context,
                    studentIDs: studentIDs,
                    source: .scopedNote(scopedNote)
                ))
            }
        } catch {
            print("Error fetching ScopedNote objects: \(error)")
        }
        
        // 3. Fetch all WorkNote objects
        do {
            let workNoteFetch = FetchDescriptor<WorkNote>(
                sortBy: [SortDescriptor(\WorkNote.createdAt, order: .reverse)]
            )
            let workNotes: [WorkNote] = try modelContext.fetch(workNoteFetch)
            for workNote in workNotes {
                var studentIDs: [UUID] = []
                if let student = workNote.student {
                    studentIDs = [student.id]
                }
                let context = "Work Check-In"
                allItems.append(UnifiedObservationItem(
                    id: workNote.id,
                    date: workNote.createdAt,
                    body: workNote.text,
                    category: .general, // WorkNote doesn't have category
                    includeInReport: false,
                    imagePath: nil,
                    contextText: context,
                    studentIDs: studentIDs,
                    source: .workNote(workNote)
                ))
            }
        } catch {
            print("Error fetching WorkNote objects: \(error)")
        }
        
        // 4. Fetch all MeetingNote objects
        do {
            let meetingNoteFetch = FetchDescriptor<MeetingNote>(
                sortBy: [SortDescriptor(\MeetingNote.createdAt, order: .reverse)]
            )
            let meetingNotes: [MeetingNote] = try modelContext.fetch(meetingNoteFetch)
            for meetingNote in meetingNotes {
                let context = meetingNote.topic != nil ? "Topic: \(meetingNote.topic!.title)" : "Meeting"
                allItems.append(UnifiedObservationItem(
                    id: meetingNote.id,
                    date: meetingNote.createdAt,
                    body: meetingNote.content,
                    category: .general, // MeetingNote doesn't have category
                    includeInReport: false,
                    imagePath: nil,
                    contextText: context,
                    studentIDs: [], // MeetingNote doesn't have student scope
                    source: .meetingNote(meetingNote)
                ))
            }
        } catch {
            print("Error fetching MeetingNote objects: \(error)")
        }
        
        // Sort all items by date (newest first)
        allItems.sort { $0.date > $1.date }
        
        loadedItems = allItems
        hasMore = false // We load everything at once for now
        loadStudentsIfNeeded(for: filteredItems)
    }
    
    private func studentIDsFromScope(_ scope: NoteScope) -> [UUID] {
        switch scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
        }
    }
    
    private func studentIDsFromScopedNoteScope(_ scope: ScopedNote.Scope) -> [UUID] {
        switch scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
        }
    }
    
    private func contextTextForScopedNote(_ scopedNote: ScopedNote) -> String? {
        if scopedNote.studentLesson != nil {
            return "Presentation"
        }
        if scopedNote.presentation != nil {
            return "Presentation"
        }
        if scopedNote.workContract != nil {
            return "Work Contract"
        }
        if scopedNote.work != nil {
            return "Work"
        }
        return nil
    }

    private var loadMoreRow: some View {
        // Since we load all notes at once, this row is not needed
        // But keeping it for potential future pagination
        EmptyView()
    }

    // MARK: - Helpers


    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = student.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    @MainActor
    private func loadStudentsIfNeeded(for items: [UnifiedObservationItem]) {
        let idsNeeded = Set(items.flatMap { $0.studentIDs })
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
    
    private func contextForNote(_ note: Note) -> UnifiedNoteEditor.NoteContext {
        if let lesson = note.lesson {
            return .lesson(lesson)
        }
        if let work = note.work {
            return .work(work)
        }
        if let studentLesson = note.studentLesson {
            return .studentLesson(studentLesson)
        }
        if let presentation = note.presentation {
            return .presentation(presentation)
        }
        if let workContract = note.workContract {
            return .workContract(workContract)
        }
        if let attendanceRecord = note.attendanceRecord {
            return .attendance(attendanceRecord)
        }
        if let workCheckIn = note.workCheckIn {
            return .workCheckIn(workCheckIn)
        }
        if let workCompletion = note.workCompletionRecord {
            return .workCompletion(workCompletion)
        }
        if let workPlanItem = note.workPlanItem {
            return .workPlanItem(workPlanItem)
        }
        if let studentMeeting = note.studentMeeting {
            return .studentMeeting(studentMeeting)
        }
        if let projectSession = note.projectSession {
            return .projectSession(projectSession)
        }
        if let communityTopic = note.communityTopic {
            return .communityTopic(communityTopic)
        }
        if let reminder = note.reminder {
            return .reminder(reminder)
        }
        if let schoolDayOverride = note.schoolDayOverride {
            return .schoolDayOverride(schoolDayOverride)
        }
        return .general
    }
}

// MARK: - Legacy Note Editor

private struct LegacyNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    @State private var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    init(title: String, text: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        _text = State(initialValue: text)
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            TextEditor(text: $text)
                .font(.system(size: 17, design: .rounded))
                .frame(minHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        .presentationSizingFitted()
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $text)
                    .font(.system(size: 17, design: .rounded))
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(trimmed)
                        }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

