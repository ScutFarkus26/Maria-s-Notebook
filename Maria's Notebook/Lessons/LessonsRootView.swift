// Maria's Notebook/Lessons/LessonsRootView.swift
//
// Split into multiple files for maintainability:
// - LessonsRootView.swift (this file) - Main view structure and body
// - LessonsRootViewPanes.swift - Column panes (subjects, lessons, detail)
// - LessonsRootViewReordering.swift - Reordering logic for groups and lessons

import SwiftUI
import SwiftData

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

// MARK: - LessonsRootView

struct LessonsRootView: View {
    // MARK: - Environment
    @Environment(\.modelContext) var modelContext
    @Environment(\.appRouter) var appRouter
    @EnvironmentObject var saveCoordinator: SaveCoordinator

    // MARK: - Data Query
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex), SortDescriptor(\Lesson.orderInGroup)])
    var lessons: [Lesson]

    // MARK: - UI State
    @StateObject var filterState = LessonsFilterState()
    @State var listSelectedSubject: String? = nil

    // MARK: - Scene Storage
    @SceneStorage("Lessons.selectedSubject") var selectedSubjectRaw: String = ""
    @SceneStorage("Lessons.searchText") var searchTextRaw: String = ""
    @SceneStorage("Lessons.displayMode") var displayModeRaw: String = LessonsDisplayMode.browse.rawValue

    // MARK: - Sheet State
    @State var lessonToSchedule: Lesson?
    @State var trackSettingsItem: TrackSettingsItem?
    @State var selectedLessonDetail: Lesson?
    @State var showingAddLesson = false
    @State var showingBulkEntry = false

    // MARK: - Reordering State
    @State var reorderableGroups: [String] = []
    @State var isOrganizingGroups: Bool = false

    // MARK: - Migration
    @AppStorage("Lessons.sortIndexMigrated") var sortIndexMigrated: Bool = false

    #if os(iOS)
    @State var editMode: EditMode = .inactive
    #endif

    // MARK: - Helper
    let helper = LessonsViewModel()

    // MARK: - Computed Properties

    var subjects: [String] {
        helper.subjects(from: lessons)
    }

    var selectedSubject: String? {
        filterState.selectedSubject
    }

    var groupsForSelectedSubject: [String] {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return [] }
        return helper.groups(for: subject, lessons: lessons)
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

    var lessonsForSubject: [Lesson] {
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return helper.filteredLessons(
            modelContext: modelContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: filterState.debouncedSearchText,
            selectedSubject: hasSearchText ? nil : filterState.selectedSubject,
            selectedGroup: nil
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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Lessons") {
                HStack(spacing: 12) {
                    Picker("Mode", selection: Binding(
                        get: { displayMode },
                        set: { displayModeRaw = $0.rawValue }
                    )) {
                        ForEach(LessonsDisplayMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    .disabled(selectedSubject == nil)

                    if displayMode == .plan && selectedSubject != nil {
                        Button {
                            isOrganizingGroups.toggle()
                        } label: {
                            Label(isOrganizingGroups ? "Done Organizing" : "Organize Groups",
                                  systemImage: isOrganizingGroups ? "checkmark.circle.fill" : "list.bullet.indent")
                        }
                        .buttonStyle(.bordered)
                    }

                    Menu {
                        Button {
                            showingAddLesson = true
                        } label: {
                            Label("New Lesson", systemImage: "plus.circle")
                        }

                        Button {
                            showingBulkEntry = true
                        } label: {
                            Label("Bulk Entry…", systemImage: "square.grid.3x3")
                        }

                        Button {
                            appRouter.requestImportLessons()
                        } label: {
                            Label("Import Lessons…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    #if os(macOS)
                    .menuStyle(.borderedButton)
                    #endif
                }
            }
            Divider()
            HStack(spacing: 0) {
                subjectsColumn
                    .frame(width: 280)

                Divider()

                lessonsContentColumn
                    .frame(maxWidth: .infinity)

                if displayMode != .plan, let selectedLesson = selectedLessonDetail {
                    Divider()
                    lessonDetailPane(lesson: selectedLesson)
                        .frame(width: 520)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedLessonDetail?.id)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task {
            await handleInitialLoad()
        }
        .onChange(of: listSelectedSubject) { _, newValue in
            handleListSelectionChange(newValue)
        }
        .onChange(of: filterState.selectedSubject) { _, newValue in
            handleSubjectChange(newValue)
        }
        .onChange(of: isOrganizingGroups) { _, newValue in
            if newValue { syncReorderableGroups() }
        }
        .onChange(of: filterState.searchText) { _, newValue in
            Task { @MainActor in searchTextRaw = newValue }
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
            _ = LessonOrderMigration.migrateSortIndices(context: modelContext)
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
            if filterState.selectedSubject != newValue {
                filterState.selectedSubject = newValue
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
            if newValue != .plan {
                isOrganizingGroups = false
            } else {
                selectedLessonDetail = nil
            }
            #if os(iOS)
            editMode = (newValue == .plan) ? .active : .inactive
            #endif
        }
    }
}
