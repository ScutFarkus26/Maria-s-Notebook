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
    case plan = "Plan"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .plan: return "list.bullet"
        }
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
    @State var isJiggling = false

    // MARK: - Scene Storage
    @SceneStorage("Lessons.selectedSubject") var selectedSubjectRaw: String = ""
    @SceneStorage("Lessons.searchText") var searchTextRaw: String = ""
    @SceneStorage("Lessons.displayMode") var displayModeRaw: String = LessonsDisplayMode.browse.rawValue

    // MARK: - Sheet State
    @State var lessonToSchedule: CDLesson?
    @State var trackSettingsItem: TrackSettingsItem?
    @State var reorderSubheadingsItem: SubheadingReorderItem?
    @State var selectedLessonDetail: CDLesson?
    @State var showingAddLesson = false
    @State var showingBulkEntry = false

    // MARK: - Reordering State
    @State var reorderableGroups: [String] = []

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

    var lessonsForSubject: [CDLesson] {
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

    var canReorderInPlanMode: Bool {
        displayMode == .plan &&
        filterState.debouncedSearchText.trimmed().isEmpty &&
        (filterState.selectedSubject?.trimmed().isEmpty == false)
    }

    var canReorder: Bool {
        isJiggling &&
        filterState.debouncedSearchText.trimmed().isEmpty &&
        (filterState.selectedSubject?.trimmed().isEmpty == false)
    }

    // MARK: - Body

    var body: some View {
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
                    Divider()
                    lessonDetailPane(lesson: selectedLesson)
                        .frame(width: 520)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveAnimation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedLessonDetail?.id)
        #if os(macOS)
        .onKeyPress(.escape) {
            if isJiggling {
                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isJiggling = false
                }
                return .handled
            }
            return .ignored
        }
        #endif
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task {
            await handleInitialLoad()
        }
        .task(id: lessonsForSubject.compactMap(\.id)) {
            await fetchPresentationHistory()
        }
        .onChange(of: listSelectedSubject) { _, newValue in
            handleListSelectionChange(newValue)
        }
        .onChange(of: filterState.selectedSubject) { _, newValue in
            handleSubjectChange(newValue)
        }
        .onChange(of: filterState.searchText) { _, newValue in
            Task { @MainActor in
                searchTextRaw = newValue
                if !newValue.trimmed().isEmpty {
                    isJiggling = false
                }
            }
        }
        .onChange(of: isJiggling) { _, newValue in
            #if os(iOS)
            editMode = newValue ? .active : .inactive
            #endif
        }
        .onChange(of: displayMode) { _, newValue in
            handleDisplayModeChange(newValue)
        }
        .sheet(item: $lessonToSchedule) { lesson in
            SchedulePresentationSheet(
                lesson: lesson,
                onPlan: { studentIDs in
                    planPresentation(for: lesson, studentIDs: studentIDs)
                },
                onCancel: { lessonToSchedule = nil }
            )
        }
        .sheet(item: $trackSettingsItem) { item in
            GroupTrackSettingsSheet(subject: item.subject, group: item.group)
        }
        .sheet(item: $reorderSubheadingsItem) { item in
            ReorderSubheadingsSheet(
                subject: item.subject,
                group: item.group,
                lessons: Array(lessons)
            )
        }
        .sheet(isPresented: $showingAddLesson) {
            AddLessonView(defaultSubject: selectedSubject)
        }
        .sheet(isPresented: $showingBulkEntry) {
            BulkLessonsEntryView(defaultSubject: selectedSubject)
        }
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
            isJiggling = false
            syncReorderableGroups()
        }
    }

    private func handleDisplayModeChange(_ newValue: LessonsDisplayMode) {
        Task { @MainActor in
            displayModeRaw = newValue.rawValue
            isJiggling = false
            if newValue == .plan {
                syncReorderableGroups()
            }
            #if os(iOS)
            editMode = isJiggling ? .active : .inactive
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
