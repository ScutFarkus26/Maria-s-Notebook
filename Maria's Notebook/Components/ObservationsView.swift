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

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
enum ObservationsHelpers {
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
#endif

struct ObservationsView: View {
    @Environment(\.modelContext) var modelContext

    // Composer
    @State private var isShowingComposer = false

    // Loaded items (unfiltered) - now includes all note types
    @State var loadedItems: [UnifiedObservationItem] = []
    @State var isLoading: Bool = false
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State var isSummarizing: Bool = false
    @State var showingSummarySheet: Bool = false
    @State var summaryMode: SummaryMode = .digest
    @State var summaryPartialDigest: NotesDigest.PartiallyGenerated?
    @State var summaryPartialNarrative: NotesNarrative.PartiallyGenerated?
    @State var summaryTask: Task<Void, Never>?

    // AI scope picker state
    @State var showingAIScopeSheet: Bool = false
    @State var aiScopeDate: Date = Date()
    @State var aiScopeContext: String?
#endif
    @State var hasMore: Bool = true
    @State var lastCursorDate: Date? // fetch notes where createdAt < lastCursorDate

    // Filters (applied in-memory) - uses ObservationsFilterService.ScopeFilter
    @State var selectedFilterTags: Set<String> = []
    @State var selectedScope: ObservationsFilterService.ScopeFilter = .all
    @State var searchText: String = ""
    // Selection state for multi-select summarize
    @State var isSelecting: Bool = false
    @State var selectedItemIDs: Set<UUID> = []

    @State var noteBeingEdited: Note?

    // Lookup cache for student names shown on rows
    @State var studentsByID: [UUID: Student] = [:]

    let pageSize: Int = 50

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    enum SummaryMode { case digest, narrative }

    /// Scope choices for AI analysis of observations.
    enum AIAnalysisScope: Identifiable {
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
                return DateFormatters.mediumDate.string(from: date)
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
            .onChange(of: loadedItems.map(\.id)) { _, _ in
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
                adaptiveWithAnimation {
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
}
