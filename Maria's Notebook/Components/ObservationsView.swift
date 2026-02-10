import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "A concise digest for observations")
struct NotesDigest {
    @Guide(description: "3–6 bullet points highlighting notable observations", .count(3...6))
    var keyPoints: [String]

    @Guide(description: "Actionable follow-ups for guides/assistants (0–5)", .count(0...5))
    var followUps: [String]

    @Guide(description: "Overall tone/sentiment (e.g., positive, neutral, concerned)")
    var sentiment: String
}
#endif

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "A concise narrative summary of observations")
struct NotesNarrative {
    @Guide(description: "A single concise paragraph narrative")
    var narrative: String
}
#endif

// UnifiedObservationItem moved to Observations/UnifiedObservationItem.swift
// Data loading delegated to ObservationsDataLoader
// Filtering delegated to ObservationsFilterService

struct ObservationsView: View {
    @Environment(\.modelContext) private var modelContext

    // Composer
    @State private var isShowingComposer = false

    // Loaded items (unfiltered) - now includes all note types
    @State private var loadedItems: [UnifiedObservationItem] = []
    @State private var isLoading: Bool = false
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State private var isSummarizing: Bool = false
    @State private var showingSummarySheet: Bool = false
    @State private var summaryMode: SummaryMode = .digest
    @State private var summaryPartialDigest: NotesDigest.PartiallyGenerated? = nil
    @State private var summaryPartialNarrative: NotesNarrative.PartiallyGenerated? = nil
    @State private var summaryTask: Task<Void, Never>? = nil
#endif
    @State private var hasMore: Bool = true
    @State private var lastCursorDate: Date? = nil // fetch notes where createdAt < lastCursorDate

    // Filters (applied in-memory) - uses ObservationsFilterService.ScopeFilter
    @State private var selectedCategory: NoteCategory? = nil
    @State private var selectedScope: ObservationsFilterService.ScopeFilter = .all
    @State private var searchText: String = ""
    // Selection state for multi-select summarize
    @State private var isSelecting: Bool = false
    @State private var selectedItemIDs: Set<UUID> = []
    
    @State private var noteBeingEdited: Note? = nil

    // Lookup cache for student names shown on rows
    @State private var studentsByID: [UUID: Student] = [:]

    private let pageSize: Int = 50

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    private enum SummaryMode { case digest, narrative }
#endif

    var body: some View {
        mainContentView
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
                NoteEditSheet(note: note) {
                    noteBeingEdited = nil
                    reloadAllNotes()
                }
            }
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
            .sheet(isPresented: $showingSummarySheet) {
                ObservationsSummarySheet(
                    mode: summaryMode,
                    isSummarizing: $isSummarizing,
                    partialDigest: summaryPartialDigest,
                    partialNarrative: summaryPartialNarrative,
                    onCancel: {
                        summaryTask?.cancel()
                        summaryTask = nil
                        isSummarizing = false
                    }
                )
            }
#endif
    }
    
    private var mainContentView: some View {
        NavigationStack {
            VStack(spacing: 8) {
                // Filters
                filterBar
                
                // List
                observationsList
            }
            .navigationTitle("Observations")
            .toolbar {
                toolbarContent
            }
        }
    }
    
    private var observationsList: some View {
        List {
            if filteredItems.isEmpty, !isLoading {
                ContentUnavailableView("No observations", systemImage: "note.text")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    observationRow(for: item)
                }
            }
        }
        .listStyle(.inset)
    }
    
    @ViewBuilder
    private func observationRow(for item: UnifiedObservationItem) -> some View {
        row(for: item)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if isSelecting {
                    Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : .secondary)
                }
            }
            .onTapGesture {
                if isSelecting {
                    if selectedItemIDs.contains(item.id) {
                        selectedItemIDs.remove(item.id)
                    } else {
                        selectedItemIDs.insert(item.id)
                    }
                } else {
                    editItem(item)
                }
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingComposer = true
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button(isSelecting ? "Done" : "Select") {
                withAnimation {
                    if isSelecting { selectedItemIDs.removeAll() }
                    isSelecting.toggle()
                }
            }
        }
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if isSelecting && !selectedItemIDs.isEmpty {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        summarizeSelected(as: .digest)
                    } label: {
                        Label("Key Points", systemImage: "list.bullet")
                    }
                    Button {
                        summarizeSelected(as: .narrative)
                    } label: {
                        Label("Narrative", systemImage: "text.justify")
                    }
                } label: {
                    Label("Summarize Selected", systemImage: "sparkles")
                }
            }
        }
#endif
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        ToolbarItem(placement: .automatic) {
            if #available(macOS 26.0, *) {
                Button {
                    startStreamingSummary(mode: .digest)
                } label: {
                    Label("Summarize", systemImage: isSummarizing ? "sparkles.rectangle.stack" : "sparkles")
                }
                .disabled(isSummarizing || loadedItems.isEmpty)
            }
        }
#endif
    }

    // MARK: - Filters UI

    private var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ObservationsFilterService.ScopeFilter.allCases) { sf in
                    Button(action: { selectedScope = sf }) {
                        HStack {
                            if selectedScope == sf {
                                Image(systemName: "checkmark")
                            }
                            Text(sf.rawValue)
                        }
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

            Menu {
                Button("All Categories") { selectedCategory = nil }
                Divider()
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    Button(action: { selectedCategory = cat }) {
                        HStack {
                            if selectedCategory == cat {
                                Image(systemName: "checkmark")
                            }
                            Text(cat.rawValue.capitalized)
                        }
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
        }
    }
    
    private func contextText(for note: Note) -> String? {
        if let lesson = note.lesson { return "Lesson: \(lesson.name)" }
        if let work = note.work { return "Work: \(work.title)" }
        if note.lessonAssignment != nil || note.studentLesson != nil { return "Presentation" }
        if note.attendanceRecord != nil { return "Attendance" }
        if note.workCheckIn != nil { return "Check-In" }
        if note.workCompletionRecord != nil { return "Completion" }
        if note.workPlanItem != nil { return "Plan" }
        if note.studentMeeting != nil { return "Meeting" }
        if note.projectSession != nil { return "Session" }
        if let communityTopic = note.communityTopic { return "Topic: \(communityTopic.title)" }
        if note.reminder != nil { return "Reminder" }
        if note.schoolDayOverride != nil { return "Override" }
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
        let trimmed = text.trimmed()
        guard !trimmed.isEmpty else { return nil }
        if let newline = trimmed.firstIndex(of: "\n") {
            return String(trimmed[..<newline])
        }
        return trimmed
    }

    // MARK: - Data (delegated to ObservationsFilterService and ObservationsDataLoader)

    private var filteredItems: [UnifiedObservationItem] {
        ObservationsFilterService.filter(
            items: loadedItems,
            category: selectedCategory,
            scope: selectedScope,
            searchText: searchText
        )
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

        loadedItems = ObservationsDataLoader.loadAllNotes(
            context: modelContext,
            contextTextProvider: { contextText(for: $0) }
        )
        hasMore = false
        loadStudentsIfNeeded(for: filteredItems)
    }

    private var loadMoreRow: some View {
        EmptyView()
    }

    // MARK: - Helpers

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    @MainActor
    private func loadStudentsIfNeeded(for items: [UnifiedObservationItem]) {
        studentsByID = ObservationsDataLoader.loadStudents(
            for: items,
            existingCache: studentsByID,
            context: modelContext
        )
    }
    
    private func contextForNote(_ note: Note) -> UnifiedNoteEditor.NoteContext {
        if let lesson = note.lesson { return .lesson(lesson) }
        if let work = note.work { return .work(work) }
        if let pres = note.lessonAssignment { return .presentation(pres) }
        if let studentLesson = note.studentLesson { return .studentLesson(studentLesson) }
        if let attendanceRecord = note.attendanceRecord { return .attendance(attendanceRecord) }
        if let workCheckIn = note.workCheckIn { return .workCheckIn(workCheckIn) }
        if let workCompletion = note.workCompletionRecord { return .workCompletion(workCompletion) }
        if let workPlanItem = note.workPlanItem { return .workPlanItem(workPlanItem) }
        if let studentMeeting = note.studentMeeting { return .studentMeeting(studentMeeting) }
        if let projectSession = note.projectSession { return .projectSession(projectSession) }
        if let communityTopic = note.communityTopic { return .communityTopic(communityTopic) }
        if let reminder = note.reminder { return .reminder(reminder) }
        if let schoolDayOverride = note.schoolDayOverride { return .schoolDayOverride(schoolDayOverride) }
        return .general
    }

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @MainActor
    private func startStreamingSummary(bodies overrideBodies: [String]? = nil, mode: SummaryMode = .digest) {
        guard !isSummarizing else { return }
        let sourceBodies: [String]
        if let overrideBodies, !overrideBodies.isEmpty {
            sourceBodies = overrideBodies
        } else {
            sourceBodies = filteredItems.prefix(50).map { "- \($0.body)" }
        }
        guard !sourceBodies.isEmpty else { return }
        let joined = (mode == .digest ? sourceBodies.joined(separator: "\n") : sourceBodies.map { $0.replacingOccurrences(of: "^- ", with: "", options: .regularExpression) }.joined(separator: "\n"))

        showingSummarySheet = true
        isSummarizing = true
        summaryMode = mode
        summaryPartialDigest = nil
        summaryPartialNarrative = nil

        let instructions = """
        You summarize Montessori classroom observations for staff.
        Be concise, factual, and avoid speculation.
        """

        let session = LanguageModelSession(instructions: instructions)
        summaryTask?.cancel()
        summaryTask = Task { @MainActor in
            do {
                switch mode {
                case .digest:
                    let stream = session.streamResponse(
                        to: "Summarize the following notes as key points, follow-ups, and sentiment:\n\(joined)",
                        generating: NotesDigest.self
                    )
                    for try await partial in stream {
                        summaryPartialDigest = partial.content
                    }
                case .narrative:
                    let stream = session.streamResponse(
                        to: "Write a single concise narrative paragraph summarizing these observations:\n\(joined)",
                        generating: NotesNarrative.self
                    )
                    for try await partial in stream {
                        summaryPartialNarrative = partial.content
                    }
                }
            } catch {
                // Ignore errors for now; user can dismiss the sheet
            }
            isSummarizing = false
            summaryTask = nil
        }
    }

    private func summarizeSelected(as mode: SummaryMode) {
        let bodies = filteredItems.filter { selectedItemIDs.contains($0.id) }.map { $0.body }
        startStreamingSummary(bodies: bodies, mode: mode)
    }
#endif

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    private struct ObservationsSummarySheet: View {
        let mode: SummaryMode
        @Binding var isSummarizing: Bool
        let partialDigest: NotesDigest.PartiallyGenerated?
        let partialNarrative: NotesNarrative.PartiallyGenerated?
        let onCancel: () -> Void

        var body: some View {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                header
                content
                footer
            }
            .padding(20)
            .frame(minWidth: 420, minHeight: 360)
            .presentationSizingFitted()
            #else
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
                .navigationTitle("Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isSummarizing ? "Stop" : "Close") { onCancel() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }

        @ViewBuilder
        private var header: some View {
            HStack {
                Text("Summary")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Button(isSummarizing ? "Stop" : "Close") { onCancel() }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch mode {
            case .digest:
                if partialDigest == nil {
                    ProgressView("Generating…")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let points = partialDigest?.keyPoints, !points.isEmpty {
                            Text("Key Points").font(.headline)
                            ForEach(points, id: \.self) { p in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill").font(.system(size: 6))
                                    Text(p)
                                }
                            }
                        }
                        if let actions = partialDigest?.followUps, !actions.isEmpty {
                            Divider().padding(.vertical, 8)
                            Text("Follow Ups").font(.headline)
                            ForEach(actions, id: \.self) { a in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                                    Text(a)
                                }
                            }
                        }
                        if let sentiment = partialDigest?.sentiment, !sentiment.isEmpty {
                            Divider().padding(.vertical, 8)
                            HStack {
                                Image(systemName: "face.smiling")
                                Text("Sentiment: \(sentiment)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            case .narrative:
                if partialNarrative == nil {
                    ProgressView("Generating…")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let text = partialNarrative?.narrative, !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private var footer: some View {
            HStack {
                Spacer()
                Button(isSummarizing ? "Stop" : "Close") { onCancel() }
                    .buttonStyle(.bordered)
            }
        }
    }
#endif
}

