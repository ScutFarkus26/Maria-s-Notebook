// Maria's Notebook/Lessons/LessonsRootView.swift
//
// Split into multiple files for maintainability:
// - LessonsRootView.swift (this file) - Main view structure and body
// - LessonsRootViewPanes.swift - Column panes (subjects, lessons, detail)
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
        case .browse: return "Browse"
        case .outline: return "Outline"
        case .map: return "Map"
        }
    }
}

/// Top-level grouping spine for the scope-and-sequence Map.
enum MapSpine: String, CaseIterable, Identifiable {
    case subject = "Subject"
    case greatLesson = "Great Lesson"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .subject: return "books.vertical"
        case .greatLesson: return "sparkles"
        }
    }
}

/// Identifies one (subject, group) thread in the scope-and-sequence map.
/// An empty `group` string represents the synthetic "ungrouped" bucket;
/// `displayName` resolves it to "Other" for UI.
struct ThreadKey: Hashable, Identifiable {
    let subject: String
    let group: String

    var id: String { "\(subject)||\(group)" }

    var displayName: String {
        group.trimmed().isEmpty ? "Other" : group
    }
}

struct TrackSettingsItem: Identifiable {
    let id = UUID()
    let subject: String
    let group: String
}

struct SubheadingReorderItem: Identifiable {
    let id = UUID()
    let subject: String
    let group: String
}

// MARK: - LessonsRootView

struct LessonsRootView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) var appRouter
    @Environment(SaveCoordinator.self) var saveCoordinator

    // MARK: - Data Query
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true), NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true), NSSortDescriptor(keyPath: \CDLesson.orderInGroup, ascending: true)])
    var lessons: FetchedResults<CDLesson>

    // MARK: - UI State
    @State var filterState = LessonsFilterState()
    @State var listSelectedSubject: String?

    // MARK: - Scene Storage
    @SceneStorage("Lessons.selectedSubject") var selectedSubjectRaw: String = ""
    @SceneStorage("Lessons.searchText") var searchTextRaw: String = ""
    @SceneStorage("Lessons.displayMode") var displayModeRaw: String = LessonsDisplayMode.browse.rawValue
    @SceneStorage("Lessons.detailPaneWidth") var detailPaneWidth: Double = 520
    @AppStorage("Lessons.mapSpine") var mapSpineRaw: String = MapSpine.subject.rawValue

    static let detailPaneMinWidth: CGFloat = 440
    static let detailPaneMaxWidth: CGFloat = 720

    // MARK: - Sheet State
    @State var lessonToSchedule: CDLesson?
    @State var trackSettingsItem: TrackSettingsItem?
    @State var reorderSubheadingsItem: SubheadingReorderItem?
    @State var selectedLessonDetail: CDLesson?
    @State var showingAddLesson = false
    @State var showingBulkEntry = false

    // MARK: - Reordering State
    @State var detailPaneDragStartWidth: CGFloat?

    @State var reorderableGroups: [String] = []
    /// Counter bumped after a subheading drag-reorder. `buildSubheadings` references it
    /// so SwiftUI re-evaluates the outline when `FilterOrderStore` changes (UserDefaults
    /// doesn't publish on its own).
    @State var subheadingOrderRevision: Int = 0

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

    var subjects: [String] {
        helper.subjects(from: Array(lessons))
    }

    var selectedSubject: String? {
        filterState.selectedSubject
    }

    var groupsForSelectedSubject: [String] {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return [] }
        return helper.groups(for: subject, lessons: Array(lessons))
    }

    var groupsFromFilteredLessons: [String] {
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        if hasSearchText {
            let unique = Set(lessonsForSubject.map { $0.group.trimmed() }.filter { !$0.isEmpty })
            return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            return groupsForSelectedSubject
        }
    }

    /// Sentinel value for the "All Stories" sidebar entry
    static let storiesSentinel = "__stories__"

    /// Sentinel value for the "Parshas" sidebar entry (parsha-indexed lesson browser)
    static let parshasSentinel = "__parshas__"

    var lessonsForSubject: [CDLesson] {
        // Parshas sentinel renders its own column (ParshaBrowseView); the regular lesson
        // list is irrelevant, so skip the fetch entirely.
        if filterState.selectedSubject == Self.parshasSentinel { return [] }
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        let isStoriesView = filterState.selectedSubject == Self.storiesSentinel
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return helper.filteredLessons(
            viewContext: viewContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            formatFilter: filterState.formatFilter,
            searchText: filterState.debouncedSearchText,
            selectedSubject: (hasSearchText || isStoriesView) ? nil : filterState.selectedSubject,
            selectedGroup: nil,
            allLessons: Array(lessons)
        ).uniqueByID
    }

    var displayMode: LessonsDisplayMode {
        LessonsDisplayMode(rawValue: displayModeRaw) ?? .browse
    }

    var mapSpine: MapSpine {
        MapSpine(rawValue: mapSpineRaw) ?? .subject
    }

    var canReorderInOutlineMode: Bool {
        displayMode == .outline &&
        filterState.debouncedSearchText.trimmed().isEmpty &&
        (filterState.selectedSubject?.trimmed().isEmpty == false)
    }

    var canReorder: Bool {
        canReorderInOutlineMode
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
        .task(id: lessonsForSubject.compactMap(\.id)) { await fetchPresentationHistory() }
        .onChange(of: listSelectedSubject) { _, newValue in handleListSelectionChange(newValue) }
        .onChange(of: filterState.selectedSubject) { _, newValue in handleSubjectChange(newValue) }
        .onChange(of: filterState.searchText) { _, newValue in handleSearchTextChange(newValue) }
        .onChange(of: displayMode) { _, newValue in handleDisplayModeChange(newValue) }
        .sheet(item: $lessonToSchedule) { lesson in lessonScheduleSheet(lesson) }
        .sheet(item: $trackSettingsItem) { item in GroupTrackSettingsSheet(subject: item.subject, group: item.group) }
        .sheet(item: $reorderSubheadingsItem) { item in
            ReorderSubheadingsSheet(subject: item.subject, group: item.group, lessons: Array(lessons))
        }
        .sheet(isPresented: $showingAddLesson) { AddLessonView(defaultSubject: selectedSubject) }
        .sheet(isPresented: $showingBulkEntry) { BulkLessonsEntryView(defaultSubject: selectedSubject) }
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
                subjectsColumn
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

        if filterState.selectedSubject == nil && !selectedSubjectRaw.trimmed().isEmpty {
            filterState.selectedSubject = selectedSubjectRaw
            listSelectedSubject = selectedSubjectRaw
        }
        if filterState.searchText.isEmpty && !searchTextRaw.isEmpty {
            filterState.searchText = searchTextRaw
        }
    }

    private func handleListSelectionChange(_ newValue: String?) {
        Task { @MainActor in
            if newValue == LessonsRootView.storiesSentinel {
                // "All Stories" selected: clear subject, set format to story
                filterState.selectedSubject = newValue
                filterState.formatFilter = .story
            } else {
                // Regular subject selected: clear story filter if it was active from sidebar
                if filterState.selectedSubject == LessonsRootView.storiesSentinel {
                    filterState.formatFilter = nil
                }
                if filterState.selectedSubject != newValue {
                    filterState.selectedSubject = newValue
                }
            }
        }
    }

    private func handleSubjectChange(_ newValue: String?) {
        Task { @MainActor in
            if listSelectedSubject != newValue {
                listSelectedSubject = newValue
            }
            selectedSubjectRaw = newValue ?? ""
            syncReorderableGroups()
        }
    }

    private func handleDisplayModeChange(_ newValue: LessonsDisplayMode) {
        Task { @MainActor in
            displayModeRaw = newValue.rawValue
            if newValue == .outline {
                syncReorderableGroups()
            }
            if newValue != .map {
                focusedThread = nil
            }
            #if os(iOS)
            editMode = newValue == .outline ? .active : .inactive
            #endif
        }
    }

    // MARK: - Presentation History

    @MainActor
    private func fetchPresentationHistory() async {
        let lessonIDs = lessonsForSubject.compactMap(\.id)
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
