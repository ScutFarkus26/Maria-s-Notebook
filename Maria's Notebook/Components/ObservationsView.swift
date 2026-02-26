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

// MARK: - Shared Helpers

private enum ObservationsHelpers {
    static func formatBodiesForSummary(_ bodies: [String], mode: ObservationsView.SummaryMode) -> String {
        if mode == .digest {
            return bodies.joined(separator: "\n")
        } else {
            return bodies.map { $0.replacingOccurrences(of: "^- ", with: "", options: .regularExpression) }
                .joined(separator: "\n")
        }
    }
    
    static func buildSummaryInstructions() -> String {
        """
        You summarize Montessori classroom observations for staff.
        Be concise, factual, and avoid speculation.
        """
    }
}

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

    // AI scope picker state
    @State private var showingAIScopeSheet: Bool = false
    @State private var aiScopeDate: Date = Date()
    @State private var aiScopeContext: String?
#endif
    @State private var hasMore: Bool = true
    @State private var lastCursorDate: Date? // fetch notes where createdAt < lastCursorDate

    // Filters (applied in-memory) - uses ObservationsFilterService.ScopeFilter
    @State private var selectedFilterTags: Set<String> = []
    @State private var selectedScope: ObservationsFilterService.ScopeFilter = .all
    @State private var searchText: String = ""
    // Selection state for multi-select summarize
    @State private var isSelecting: Bool = false
    @State private var selectedItemIDs: Set<UUID> = []
    
    @State private var noteBeingEdited: Note?

    // Lookup cache for student names shown on rows
    @State private var studentsByID: [UUID: Student] = [:]

    private let pageSize: Int = 50

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    fileprivate enum SummaryMode { case digest, narrative }

    /// Scope choices for AI analysis of observations.
    fileprivate enum AIAnalysisScope: Identifiable {
        case today
        case specificDay(Date)
        case context(String)
        case selectedNotes

        var id: String {
            switch self {
            case .today: return "today"
            case .specificDay(let date): return "day-\(date.timeIntervalSince1970)"
            case .context(let ctx): return "context-\(ctx)"
            case .selectedNotes: return "selected"
            }
        }

        var label: String {
            switch self {
            case .today: return "Today's Observations"
            case .specificDay(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: date)
            case .context(let ctx): return ctx
            case .selectedNotes: return "Selected Notes"
            }
        }
    }
#endif

    var body: some View {
        mainContentView
            .searchable(text: $searchText)
            .onAppear { loadFirstPageIfNeeded() }
            .onChange(of: loadedItems.map { $0.id }) { _, _ in
                loadStudentsIfNeeded(for: filteredItems)
            }
            .onChange(of: selectedFilterTags) { _, _ in
                // Tags are filtered in-memory; keep pages as-is
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
            .sheet(isPresented: $showingAIScopeSheet) {
                AIDayPickerSheet(date: $aiScopeDate) { pickedDate in
                    showingAIScopeSheet = false
                    analyzeScope(.specificDay(pickedDate), mode: .digest)
                }
            }
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
        ToolbarItem(placement: .automatic) {
            if #available(macOS 26.0, *) {
                aiMenu
                    .disabled(isSummarizing || loadedItems.isEmpty)
            }
        }
#endif
    }

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @available(macOS 26.0, *)
    private var aiMenu: some View {
        Menu {
            // MARK: Today
            Button {
                analyzeScope(.today, mode: .digest)
            } label: {
                Label("Today", systemImage: "calendar")
            }

            // MARK: Specific Day
            Button {
                showingAIScopeSheet = true
            } label: {
                Label("Pick a Day…", systemImage: "calendar.badge.clock")
            }

            // MARK: By Context / Period
            let contexts = uniqueContexts
            if !contexts.isEmpty {
                Divider()
                Menu {
                    ForEach(contexts, id: \.self) { ctx in
                        Button {
                            analyzeScope(.context(ctx), mode: .digest)
                        } label: {
                            Text(ctx)
                        }
                    }
                } label: {
                    Label("By Context", systemImage: "tray.2")
                }
            }

            // MARK: Selected Notes
            if isSelecting && !selectedItemIDs.isEmpty {
                Divider()
                Button {
                    analyzeScope(.selectedNotes, mode: .digest)
                } label: {
                    Label("Selected Notes (\(selectedItemIDs.count))", systemImage: "checkmark.circle")
                }
            }

            Divider()

            // MARK: Summary mode toggle
            Menu {
                Button {
                    startStreamingSummary(mode: .digest)
                } label: {
                    Label("Key Points", systemImage: "list.bullet")
                }
                Button {
                    startStreamingSummary(mode: .narrative)
                } label: {
                    Label("Narrative", systemImage: "text.justify")
                }
            } label: {
                Label("Summarize All Visible", systemImage: "sparkles.rectangle.stack")
            }
        } label: {
            Label("AI", systemImage: isSummarizing ? "sparkles.rectangle.stack" : "sparkles")
        }
    }
#endif

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
                Button("All Tags") {
                    selectedFilterTags.removeAll()
                }

                Divider()

                let allUsedTags = Set(loadedItems.flatMap { $0.tags }).sorted { TagHelper.tagName($0) < TagHelper.tagName($1) }
                ForEach(allUsedTags, id: \.self) { tag in
                    Button(action: {
                        if selectedFilterTags.contains(tag) {
                            selectedFilterTags.remove(tag)
                        } else {
                            selectedFilterTags.insert(tag)
                        }
                    }) {
                        HStack {
                            if selectedFilterTags.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                            Text(TagHelper.tagName(tag))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedFilterTags.isEmpty ? "All Tags" : "\(selectedFilterTags.count) tag\(selectedFilterTags.count == 1 ? "" : "s")")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: UnifiedObservationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.tint)
                
                if !item.tags.isEmpty {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }
                
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
            filterTags: selectedFilterTags,
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
        guard SystemLanguageModel.default.isAvailable else { return }
        let sourceBodies: [String]
        if let overrideBodies, !overrideBodies.isEmpty {
            sourceBodies = overrideBodies
        } else {
            sourceBodies = filteredItems.prefix(50).map { "- \($0.body)" }
        }
        guard !sourceBodies.isEmpty else { return }
        let joined = ObservationsHelpers.formatBodiesForSummary(sourceBodies, mode: mode)

        showingSummarySheet = true
        isSummarizing = true
        summaryMode = mode
        summaryPartialDigest = nil
        summaryPartialNarrative = nil

        let instructions = ObservationsHelpers.buildSummaryInstructions()
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
                #if DEBUG
                print("Observations summary failed: \(error)")
                #endif
            }
            isSummarizing = false
            summaryTask = nil
        }
    }

    private func summarizeSelected(as mode: SummaryMode) {
        let bodies = filteredItems.filter { selectedItemIDs.contains($0.id) }.map { $0.body }
        startStreamingSummary(bodies: bodies, mode: mode)
    }

    // MARK: - AI Scope Analysis

    /// Unique context strings from the current filtered items, for the "By Context" menu.
    private var uniqueContexts: [String] {
        let all = filteredItems.compactMap { $0.contextText }
        // Deduplicate while preserving order
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    /// Runs the AI summary for a given scope.
    @MainActor
    private func analyzeScope(_ scope: AIAnalysisScope, mode: SummaryMode) {
        let calendar = Calendar.current
        let bodies: [String]

        switch scope {
        case .today:
            let todayStart = calendar.startOfDay(for: Date())
            bodies = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == todayStart }
                .map { "- \($0.body)" }

        case .specificDay(let date):
            let dayStart = calendar.startOfDay(for: date)
            bodies = filteredItems
                .filter { calendar.startOfDay(for: $0.date) == dayStart }
                .map { "- \($0.body)" }

        case .context(let ctx):
            bodies = filteredItems
                .filter { $0.contextText == ctx }
                .map { "- \($0.body)" }

        case .selectedNotes:
            bodies = filteredItems
                .filter { selectedItemIDs.contains($0.id) }
                .map { "- \($0.body)" }
        }

        guard !bodies.isEmpty else { return }
        startStreamingSummary(bodies: bodies, mode: mode)
    }
#endif

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    // MARK: - Day Picker Sheet

    private struct AIDayPickerSheet: View {
        @Binding var date: Date
        let onConfirm: (Date) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            #if os(macOS)
            VStack(spacing: 16) {
                Text("Pick a Day")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Analyze") { onConfirm(date) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 340)
            .presentationSizingFitted()
            #else
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Button("Analyze") { onConfirm(date) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .navigationTitle("Pick a Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
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

