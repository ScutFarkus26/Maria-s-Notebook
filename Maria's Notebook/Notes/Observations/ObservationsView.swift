import SwiftUI
import CoreData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "One evidence-linked finding from Montessori classroom records")
struct GroundedObservationFinding {
    @Guide(description: "A concise factual statement or question that does not diagnose or judge readiness")
    var text: String

    @Guide(description: "Source keys exactly as supplied, such as O1 or O2", .count(1...4))
    var sourceKeys: [String]
}

@available(macOS 26.0, *)
@Generable(description: "An evidence-linked reflection on classroom observations")
struct NotesDigest {
    @Guide(description: "Directly supported factual observations", .count(0...6))
    var factualObservations: [GroundedObservationFinding]

    @Guide(description: "Patterns present in at least two different source records", .count(0...5))
    var repeatedPatterns: [GroundedObservationFinding]

    @Guide(description: "Neutral questions the guide may choose to observe next", .count(0...5))
    var questionsToObserveNext: [GroundedObservationFinding]
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
        You help a trained Montessori guide review their own classroom records.
        Use only the supplied source records. Be concise and factual. Never diagnose,
        classify sentiment, infer emotion, score readiness, or decide a next lesson.
        Preserve the guide's authority and cite the supplied source keys.
        """
    }
}
#endif

struct ObservationsView: View {
    @Environment(\.managedObjectContext) var viewContext
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    // Composer
    @State private var isShowingComposer = false

    // Loaded items (unfiltered) - now includes all note types
    @State var loadedItems: [UnifiedObservationItem] = []
    @State var isLoading: Bool = false
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State var isSummarizing: Bool = false
    @State var showingSummarySheet: Bool = false
    @State var summaryMode: SummaryMode = .digest
    @State var summaryDigest: NotesDigest?
    @State var summaryNarrative: NotesNarrative?
    @State var summaryNarrativeDraft: String = ""
    @State var summarySources: [String: EvidenceReference] = [:]
    @State var summaryMissingEvidence: [EvidenceReference] = []
    @State var summaryErrorMessage: String?
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

    @State var noteBeingEdited: CDNote?

    // Lookup cache for student names shown on rows
    @State var studentsByID: [UUID: CDStudent] = [:]

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
            #if os(iOS)
            .sheet(item: $noteBeingEdited) { note in
                NoteEditSheet(note: note) {
                    noteBeingEdited = nil
                    reloadAllNotes()
                }
            }
            #else
            .onChange(of: noteBeingEdited?.id) { _, _ in
                guard let noteID = noteBeingEdited?.id else { return }
                openWindow(id: "NoteEditorWindow", value: noteID)
                noteBeingEdited = nil
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .noteDidSave)) { _ in
                reloadAllNotes()
            }
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
            .sheet(isPresented: $showingAIScopeSheet) {
                AIDayPickerSheet(date: $aiScopeDate) { pickedDate in
                    showingAIScopeSheet = false
                    // Dismissing the sheet puts AppKit inside the parent
                    // window's layout pass; starting the reflection writes
                    // state the Reflect toolbar item reads. Doing both in one
                    // turn is what crashed the window.
                    afterLayout { analyzeScope(.specificDay(pickedDate), mode: .digest) }
                }
            }
            .sheet(isPresented: $showingSummarySheet) {
                ObservationsSummarySheet(
                    mode: summaryMode,
                    isSummarizing: $isSummarizing,
                    digest: summaryDigest,
                    narrative: summaryNarrative,
                    narrativeDraft: $summaryNarrativeDraft,
                    sources: summarySources,
                    missingEvidence: summaryMissingEvidence,
                    errorMessage: summaryErrorMessage,
                    onOpenSource: { reference in
                        showingSummarySheet = false
                        guard reference.entityKind == .note,
                              let item = loadedItems.first(where: { $0.id == reference.entityID }),
                              case .note(let note) = item.source else { return }
                        noteBeingEdited = note
                    },
                    onCancel: {
                        summaryTask?.cancel()
                        summaryTask = nil
                        // Same bounce, same reason: Stop closes this sheet,
                        // and `isSummarizing` is read by a toolbar item.
                        afterLayout { isSummarizing = false }
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
