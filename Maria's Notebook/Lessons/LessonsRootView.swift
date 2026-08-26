// Maria's Notebook/Lessons/LessonsRootView.swift
//
// Split into multiple files for maintainability:
// - LessonsRootView.swift (this file) - Main view structure and body
// - LessonsRootViewPanes.swift - Column panes (areas, lessons, detail)
// - LessonsRootViewReordering.swift - Reordering logic for groups and lessons

import SwiftUI
import CoreData

// MARK: - Supporting Types

/// Top-level grouping spine for the scope-and-sequence Map.
enum MapSpine: String, CaseIterable, Identifiable {
    case area = "Area"
    case greatLesson = "Great Lesson"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .area: return "books.vertical"
        case .greatLesson: return "sparkles"
        }
    }
}

/// Identifies one (area, sequence) thread in the scope-and-sequence map.
/// An empty `sequence` string represents the synthetic "ungrouped" bucket;
/// `displayName` resolves it to "Other" for UI.
struct ThreadKey: Hashable, Identifiable {
    let area: String
    let sequence: String

    var id: String { "\(area)||\(sequence)" }

    var displayName: String {
        sequence.trimmed().isEmpty ? "Other" : sequence
    }
}

struct TrackSettingsItem: Identifiable {
    let id = UUID()
    let area: String
    let sequence: String
}

struct SectionReorderItem: Identifiable {
    let id = UUID()
    let area: String
    let sequence: String
}

/// Drives the Add Lesson sheet. `source` carries the "insert after" lesson when entry
/// came from a pill's context menu (otherwise nil for a plain "Add Lesson" action).
struct AddLessonContext: Identifiable {
    let id = UUID()
    let source: CDLesson?
}

// MARK: - LessonsRootView

struct LessonsRootView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) var appRouter
    @Environment(SaveCoordinator.self) var saveCoordinator

    // MARK: - Data Query
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
        NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true),
        NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
    ])
    var lessons: FetchedResults<CDLesson>

    // MARK: - UI State
    @State var filterState = LessonsFilterState()

    // MARK: - Scene Storage
    @SceneStorage("Lessons.selectedArea") var selectedAreaRaw: String = ""
    @SceneStorage("Lessons.searchText") var searchTextRaw: String = ""
    @SceneStorage("Lessons.detailPaneWidth") var detailPaneWidth: Double = 520
    @SceneStorage("Lessons.showingParshas") var showingParshas: Bool = false
    @AppStorage("Lessons.mapSpine") var mapSpineRaw: String = MapSpine.area.rawValue

    static let detailPaneMinWidth: CGFloat = 440
    static let detailPaneMaxWidth: CGFloat = 720

    // MARK: - Sheet State
    @State var lessonToSchedule: CDLesson?
    @State var trackSettingsItem: TrackSettingsItem?
    @State var reorderSectionsItem: SectionReorderItem?
    @State var selectedLessonDetail: CDLesson?
    @State var showingBulkEntry = false
    /// Non-nil ⇒ the Add Lesson sheet is presented. Using `.sheet(item:)` guarantees the
    /// source lesson (when present) is captured before the sheet content evaluates,
    /// which is why this isn't split into a separate `Bool` + `CDLesson?` pair.
    @State var addLessonContext: AddLessonContext?

    // MARK: - Editing State
    @State var isEditingMap: Bool = false

    // MARK: - Reordering State
    @State var detailPaneDragStartWidth: CGFloat?

    @State var reorderableSequences: [String] = []

    // MARK: - Map Mode State
    @State var focusedThread: ThreadKey?

    // MARK: - Presentation History State
    @State var statusCounts: [UUID: Int]?
    @State var lastPresentedDates: [UUID: Date]?

    // MARK: - Migration
    @AppStorage(UserDefaultsKeys.lessonsSortIndexMigrated) var sortIndexMigrated: Bool = false

    #if os(iOS)
    @State var editMode: EditMode = .inactive
    #endif

    // MARK: - Helper
    let helper = LessonsViewModel()

    // MARK: - Computed Properties

    var areas: [String] {
        helper.areas(from: Array(lessons))
    }

    var selectedArea: String? {
        filterState.selectedArea
    }

    var groupsForSelectedArea: [String] {
        guard let area = selectedArea, !area.trimmed().isEmpty else { return [] }
        return helper.groups(for: area, lessons: Array(lessons))
    }

    var groupsFromFilteredLessons: [String] {
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        if hasSearchText {
            let unique = Set(lessonsForArea.map { $0.sequence.trimmed() }.filter { !$0.isEmpty })
            return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            return groupsForSelectedArea
        }
    }

    var lessonsForArea: [CDLesson] {
        // Parshas mode renders its own view (ParshaBrowseView); skip the fetch entirely.
        if showingParshas { return [] }
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return helper.filteredLessons(
            viewContext: viewContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            formatFilter: filterState.formatFilter,
            searchText: filterState.debouncedSearchText,
            selectedArea: hasSearchText ? nil : filterState.selectedArea,
            selectedSequence: nil,
            allLessons: Array(lessons)
        ).uniqueByID
    }

    var mapSpine: MapSpine {
        MapSpine(rawValue: mapSpineRaw) ?? .area
    }

    var canReorder: Bool {
        filterState.debouncedSearchText.trimmed().isEmpty
    }

    var canShowEditMapButton: Bool {
        filterState.debouncedSearchText.trimmed().isEmpty && !showingParshas
    }

    // MARK: - Body

    var body: some View {
        lessonsMainLayout
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveAnimation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedLessonDetail?.id)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task { await handleInitialLoad() }
        .task { openPendingLesson() }
        .onChange(of: appRouter.pendingLessonID) { openPendingLesson() }
        .task(id: lessonsForArea.compactMap(\.id)) { await fetchPresentationHistory() }
        .onChange(of: filterState.selectedArea) { _, newValue in handleAreaChange(newValue) }
        .onChange(of: filterState.searchText) { _, newValue in handleSearchTextChange(newValue) }
        .sheet(item: $lessonToSchedule) { lesson in lessonScheduleSheet(lesson) }
        .sheet(item: $trackSettingsItem) { item in
            SequenceTrackSettingsSheet(area: item.area, sequence: item.sequence)
        }
        .sheet(item: $reorderSectionsItem) { item in
            ReorderSectionsSheet(area: item.area, sequence: item.sequence, lessons: Array(lessons))
        }
        .sheet(item: $addLessonContext) { context in
            AddLessonView(
                defaultArea: context.source?.area ?? selectedArea,
                defaultSequence: context.source?.sequence,
                defaultSection: context.source?.section,
                onLessonCreated: { newLesson in
                    if let source = context.source {
                        insertLessonAfter(newLesson: newLesson, after: source)
                    }
                }
            )
        }
        .sheet(isPresented: $showingBulkEntry) { BulkLessonsEntryView(defaultArea: selectedArea) }
    }

    /// Reveals a lesson requested from elsewhere in the app — today, the
    /// album reader's "Notebook Lesson" jump on a linked album page.
    private func openPendingLesson() {
        guard let id = appRouter.pendingLessonID else { return }
        _ = appRouter.consumePendingLessonID()
        guard let lesson = lessons.first(where: { $0.id == id }) else { return }
        // Clear any area filter that would hide the lesson from its column.
        if !lesson.area.trimmed().isEmpty, filterState.selectedArea != lesson.area {
            filterState.selectedArea = lesson.area
        }
        selectedLessonDetail = lesson
    }

    private func lessonScheduleSheet(_ lesson: CDLesson) -> some View {
        SchedulePresentationSheet(
            lesson: lesson,
            onPlan: { studentIDs in planPresentation(for: lesson, studentIDs: studentIDs) },
            onCancel: { lessonToSchedule = nil }
        )
    }

    private func handleSearchTextChange(_ newValue: String) {
        Task { @MainActor in
            searchTextRaw = newValue
        }
    }

    private var lessonsMainLayout: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            ViewHeader(title: "Lessons") { headerTrailingControls }
            Divider()
            #endif
            HStack(spacing: 0) {
                lessonsContentColumn
                    .frame(maxWidth: .infinity)

                if let selectedLesson = selectedLessonDetail {
                    resizableDetailDivider
                    lessonDetailPane(lesson: selectedLesson)
                        .frame(width: CGFloat(detailPaneWidth))
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .navigationTitle("Lessons")
        #if os(macOS)
        .searchable(text: $filterState.searchText, placement: .toolbar, prompt: "Search lessons")
        .toolbar { lessonsToolbarContent }
        #endif
    }

    /// Vertical divider that resizes the detail pane when dragged.
    private var resizableDetailDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(Divider())
            .frame(width: 6)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
            .gesture(detailDividerDragGesture)
    }

    private var detailDividerDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if detailPaneDragStartWidth == nil {
                    detailPaneDragStartWidth = CGFloat(detailPaneWidth)
                }
                let start = detailPaneDragStartWidth ?? CGFloat(detailPaneWidth)
                let raw = start - value.translation.width
                let clamped = min(Self.detailPaneMaxWidth, max(Self.detailPaneMinWidth, raw))
                detailPaneWidth = Double(clamped)
            }
            .onEnded { _ in detailPaneDragStartWidth = nil }
    }

    // MARK: - Event Handlers

    @MainActor
    private func handleInitialLoad() async {
        if !sortIndexMigrated {
            _ = LessonOrderMigration.migrateSortIndices(context: viewContext)
            sortIndexMigrated = true
        }

        if filterState.selectedArea == nil && !selectedAreaRaw.trimmed().isEmpty {
            filterState.selectedArea = selectedAreaRaw
        }
        if filterState.searchText.isEmpty && !searchTextRaw.isEmpty {
            filterState.searchText = searchTextRaw
        }
    }

    private func handleAreaChange(_ newValue: String?) {
        Task { @MainActor in
            selectedAreaRaw = newValue ?? ""
            isEditingMap = false
            // Preserve the drilled-in thread when this area change is a side-effect of
            // selecting it: onSelectThread / locateLessonInMap set `selectedArea`
            // alongside `focusedThread`, and clearing the focus here would bounce the
            // user back to the area instead of opening the sequence they tapped.
            // Only drop the focus when the area genuinely changed away from it.
            if focusedThread?.area != newValue {
                focusedThread = nil
            }
            syncReorderableSequences()
        }
    }

    // MARK: - Presentation History

    @MainActor
    private func fetchPresentationHistory() async {
        let lessonIDs = lessonsForArea.compactMap(\.id)
        guard !lessonIDs.isEmpty else {
            statusCounts = nil
            lastPresentedDates = nil
            return
        }

        // Fetch last presented dates
        let history = LessonsPresentationHistoryProvider.fetchPresentationHistory(
            lessonIDs: lessonIDs,
            context: viewContext
        )
        lastPresentedDates = history.lastPresented

        // Compute status counts (students needing each lesson)
        // This uses the existing helper method if available, or we compute it here
        statusCounts = helper.computeLessonStatusCounts(
            for: lessonIDs,
            context: viewContext
        )
    }
}
