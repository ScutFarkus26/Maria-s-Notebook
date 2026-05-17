// Maria's Notebook/Lessons/LessonsRootView.swift
//
// Split into multiple files for maintainability:
// - LessonsRootView.swift (this file) - Main view structure and body
// - LessonsRootViewPanes.swift - Column panes (areas, lessons, detail)
// - LessonsRootViewReordering.swift - Reordering logic for groups and lessons

import SwiftUI
import CoreData

// MARK: - Supporting Types

enum LessonsDisplayMode: String, CaseIterable, Identifiable {
    case browse = "Browse"
    // rawValue retained as "Plan" so existing @SceneStorage values continue to resolve.
    case outline = "Plan"
    case map = "Map"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .outline: return "list.bullet.indent"
        case .map: return "chart.bar.doc.horizontal"
        }
    }

    var displayName: String {
        switch self {
        case .browse: return "Cards"
        case .outline: return "List"
        case .map: return "Map"
        }
    }
}

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

// MARK: - LessonsRootView

struct LessonsRootView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) var appRouter
    @Environment(SaveCoordinator.self) var saveCoordinator

    // MARK: - Data Query
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.area, ascending: true), NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true), NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)])
    var lessons: FetchedResults<CDLesson>

    // MARK: - UI State
    @State var filterState = LessonsFilterState()
    @State var listSelectedArea: String?

    // MARK: - Scene Storage
    @SceneStorage("Lessons.selectedArea") var selectedAreaRaw: String = ""
    @SceneStorage("Lessons.searchText") var searchTextRaw: String = ""
    @SceneStorage("Lessons.displayMode") var displayModeRaw: String = LessonsDisplayMode.outline.rawValue
    @SceneStorage("Lessons.detailPaneWidth") var detailPaneWidth: Double = 520
    @AppStorage("Lessons.mapSpine") var mapSpineRaw: String = MapSpine.area.rawValue

    static let detailPaneMinWidth: CGFloat = 440
    static let detailPaneMaxWidth: CGFloat = 720

    // MARK: - Sheet State
    @State var lessonToSchedule: CDLesson?
    @State var trackSettingsItem: TrackSettingsItem?
    @State var reorderSectionsItem: SectionReorderItem?
    @State var selectedLessonDetail: CDLesson?
    @State var showingAddLesson = false
    @State var showingBulkEntry = false

    // MARK: - Editing State
    @State var isEditingSequence: Bool = false

    // MARK: - Reordering State
    @State var detailPaneDragStartWidth: CGFloat?

    @State var reorderableSequences: [String] = []
    /// Counter bumped after a section drag-reorder. `buildSections` references it
    /// so SwiftUI re-evaluates the outline when `FilterOrderStore` changes (UserDefaults
    /// doesn't publish on its own).
    @State var sectionOrderRevision: Int = 0

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

    /// Sentinel value for the "All Stories" sidebar entry
    static let storiesSentinel = "__stories__"

    /// Sentinel value for the "Parshas" sidebar entry (parsha-indexed lesson browser)
    static let parshasSentinel = "__parshas__"

    /// Sentinel value for the "All Lessons" sidebar entry (cross-area browser)
    static let allLessonsSentinel = "__all__"

    var lessonsForArea: [CDLesson] {
        // Parshas sentinel renders its own column (ParshaBrowseView); the regular lesson
        // list is irrelevant, so skip the fetch entirely.
        if filterState.selectedArea == Self.parshasSentinel { return [] }
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        let isStoriesView = filterState.selectedArea == Self.storiesSentinel
        let isAllLessons  = filterState.selectedArea == Self.allLessonsSentinel
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return helper.filteredLessons(
            viewContext: viewContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            formatFilter: filterState.formatFilter,
            searchText: filterState.debouncedSearchText,
            selectedArea: (hasSearchText || isStoriesView || isAllLessons) ? nil : filterState.selectedArea,
            selectedSequence: nil,
            allLessons: Array(lessons)
        ).uniqueByID
    }

    var displayMode: LessonsDisplayMode {
        LessonsDisplayMode(rawValue: displayModeRaw) ?? .browse
    }

    var mapSpine: MapSpine {
        MapSpine(rawValue: mapSpineRaw) ?? .area
    }

    var canReorderInOutlineMode: Bool {
        guard displayMode == .outline, isEditingSequence else { return false }
        guard filterState.debouncedSearchText.trimmed().isEmpty else { return false }
        guard let area = filterState.selectedArea,
              !area.trimmed().isEmpty,
              area != Self.allLessonsSentinel,
              area != Self.storiesSentinel else { return false }
        return true
    }

    var canReorder: Bool {
        canReorderInOutlineMode
    }

    var canShowEditSequenceButton: Bool {
        guard displayMode == .outline else { return false }
        guard filterState.debouncedSearchText.trimmed().isEmpty else { return false }
        guard let area = filterState.selectedArea,
              !area.trimmed().isEmpty,
              area != Self.allLessonsSentinel,
              area != Self.storiesSentinel,
              area != Self.parshasSentinel else { return false }
        return true
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
        .task(id: lessonsForArea.compactMap(\.id)) { await fetchPresentationHistory() }
        .onChange(of: listSelectedArea) { _, newValue in handleListSelectionChange(newValue) }
        .onChange(of: filterState.selectedArea) { _, newValue in handleAreaChange(newValue) }
        .onChange(of: filterState.searchText) { _, newValue in handleSearchTextChange(newValue) }
        .onChange(of: displayMode) { _, newValue in handleDisplayModeChange(newValue) }
        .sheet(item: $lessonToSchedule) { lesson in lessonScheduleSheet(lesson) }
        .sheet(item: $trackSettingsItem) { item in SequenceTrackSettingsSheet(area: item.area, sequence: item.sequence) }
        .sheet(item: $reorderSectionsItem) { item in
            ReorderSectionsSheet(area: item.area, sequence: item.sequence, lessons: Array(lessons))
        }
        .sheet(isPresented: $showingAddLesson) { AddLessonView(defaultArea: selectedArea) }
        .sheet(isPresented: $showingBulkEntry) { BulkLessonsEntryView(defaultArea: selectedArea) }
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
            ViewHeader(title: "Lessons") { headerTrailingControls }
            Divider()
            HStack(spacing: 0) {
                areasColumn
                    .frame(width: 280)

                Divider()

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
            listSelectedArea = selectedAreaRaw
        }
        if filterState.searchText.isEmpty && !searchTextRaw.isEmpty {
            filterState.searchText = searchTextRaw
        }
    }

    private func handleListSelectionChange(_ newValue: String?) {
        Task { @MainActor in
            switch newValue {
            case LessonsRootView.storiesSentinel:
                filterState.selectedArea = newValue
                filterState.formatFilter = .story
            case LessonsRootView.allLessonsSentinel, LessonsRootView.parshasSentinel, nil:
                if filterState.selectedArea == LessonsRootView.storiesSentinel {
                    filterState.formatFilter = nil
                }
                filterState.selectedArea = newValue
            default:
                // Regular area selected: clear story filter if it was active from sidebar
                if filterState.selectedArea == LessonsRootView.storiesSentinel {
                    filterState.formatFilter = nil
                }
                if filterState.selectedArea != newValue {
                    filterState.selectedArea = newValue
                }
            }
        }
    }

    private func handleAreaChange(_ newValue: String?) {
        Task { @MainActor in
            if listSelectedArea != newValue {
                listSelectedArea = newValue
            }
            selectedAreaRaw = newValue ?? ""
            isEditingSequence = false
            syncReorderableSequences()
        }
    }

    private func handleDisplayModeChange(_ newValue: LessonsDisplayMode) {
        Task { @MainActor in
            displayModeRaw = newValue.rawValue
            isEditingSequence = false
            if newValue == .outline {
                syncReorderableSequences()
            }
            if newValue != .map {
                focusedThread = nil
            }
            #if os(iOS)
            editMode = .inactive
            #endif
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
