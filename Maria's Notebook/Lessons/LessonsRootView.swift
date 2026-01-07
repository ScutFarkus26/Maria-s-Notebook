// Maria's Notebook/Lessons/LessonsRootView.swift

import SwiftUI
import SwiftData

struct LessonsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // Data
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group), SortDescriptor(\Lesson.orderInGroup)])
    private var lessons: [Lesson]

    // UI state
    @StateObject private var filterState = LessonsFilterState()

    // Selection
    @State private var selectedLesson: Lesson?
    // Intermediate state for List selection to avoid publishing during view updates
    @State private var listSelectedSubject: String? = nil

    @SceneStorage("Lessons.selectedSubject") private var selectedSubjectRaw: String = ""
    @SceneStorage("Lessons.searchText") private var searchTextRaw: String = ""

    // Modes
    @State private var isReorderMode: Bool = false
    @State private var reorderScope: ReorderScope = .lessons

    // Local state for responsive reordering
    @State private var reorderableGroups: [String] = []

    enum ReorderScope: String, CaseIterable, Identifiable {
        case lessons = "Lessons"
        case groups = "Albums"
        var id: String { rawValue }
    }

    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private let helper = LessonsViewModel()

    // MARK: - Derived

    private var subjects: [String] {
        helper.subjects(from: lessons)
    }

    private var selectedSubject: String? {
        filterState.selectedSubject
    }


    private var groupsForSelectedSubject: [String] {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return [] }
        return helper.groups(for: subject, lessons: lessons)
    }

    // Filtered lessons for the entire subject (all groups)
    private var lessonsForSubject: [Lesson] {
        return helper.filteredLessons(
            modelContext: modelContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: filterState.debouncedSearchText,
            selectedSubject: filterState.selectedSubject,
            selectedGroup: nil // We now want ALL groups for the subject
        )
    }

    private var canReorderLessons: Bool {
        isReorderMode &&
        reorderScope == .lessons &&
        filterState.debouncedSearchText.trimmed().isEmpty &&
        (filterState.selectedSubject?.trimmed().isEmpty == false)
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            subjectsColumn
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        } content: {
            lessonsListColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 320, max: 500)
        } detail: {
            lessonDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task {
            await MainActor.run {
                if filterState.selectedSubject == nil && !selectedSubjectRaw.trimmed().isEmpty {
                    filterState.selectedSubject = selectedSubjectRaw
                    listSelectedSubject = selectedSubjectRaw
                }
                if filterState.searchText.isEmpty && !searchTextRaw.isEmpty {
                    filterState.searchText = searchTextRaw
                }
            }
        }
        .onChange(of: listSelectedSubject) { _, newValue in
            Task { @MainActor in
                // Only update if different to avoid loop
                if filterState.selectedSubject != newValue {
                    filterState.selectedSubject = newValue
                }
            }
        }
        .onChange(of: filterState.selectedSubject) { _, newValue in
            Task { @MainActor in
                // Sync to list selection if different
                if listSelectedSubject != newValue {
                    listSelectedSubject = newValue
                }
                // Handle side effects
                selectedSubjectRaw = newValue ?? ""
                selectedLesson = nil
                syncReorderableGroups()
            }
        }
        .onChange(of: filterState.searchText) { _, newValue in
            Task { @MainActor in
                searchTextRaw = newValue
            }
        }
        .onChange(of: isReorderMode) { _, newValue in
            Task { @MainActor in
                #if os(iOS)
                editMode = newValue ? .active : .inactive
                #endif
                if newValue {
                    syncReorderableGroups()
                } else {
                    reorderScope = .lessons
                }
            }
        }
        .onChange(of: reorderScope) { _, newValue in
            Task { @MainActor in
                if newValue == .groups {
                    syncReorderableGroups()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if isReorderMode {
                    Picker("Reorder Scope", selection: $reorderScope) {
                        ForEach(ReorderScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                Toggle("Reorder", isOn: $isReorderMode)
                    .toggleStyle(.button)
                    .disabled(selectedSubject == nil)
            }
        }
    }

    // MARK: - Columns

    private var subjectsColumn: some View {
        List(selection: $listSelectedSubject) {
            ForEach(subjects, id: \.self) { subject in
                Text(subject)
                    .tag(subject)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Albums")
    }

    private var lessonsListColumn: some View {
        VStack(spacing: 0) {
            if let subject = selectedSubject, !subject.trimmed().isEmpty {
                if isReorderMode && reorderScope == .groups {
                    // Group Reorder Mode
                    List {
                        ForEach(reorderableGroups, id: \.self) { group in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(AppColors.color(forSubject: subject))
                                Text(group)
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                        .onMove(perform: moveGroups)
                    }
                    .lessonsMiddleColumnListStyle()
                    .navigationTitle(subject)
                    .id("GroupReorderList")
                } else {
                    // Standard Lesson List Mode
                    // Include an "Ungrouped" section for lessons with no group
                    let ungroupedLabel = "Ungrouped"
                    let baseGroups = groupsForSelectedSubject
                    let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
                    let displayGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

                    List(selection: $selectedLesson) {
                        ForEach(displayGroups, id: \.self) { group in
                            let groupLessons = lessonsForSubject.filter { lesson in
                                let lessonGroupTrimmed = lesson.group.trimmed()
                                if group == ungroupedLabel {
                                    return lessonGroupTrimmed.isEmpty
                                } else {
                                    return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
                                }
                            }.sorted { lhs, rhs in
                                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                            }

                            if !groupLessons.isEmpty {
                                Section(header: Text(group)) {
                                    ForEach(groupLessons, id: \.self) { lesson in
                                        LessonRow(lesson: lesson)
                                            .tag(lesson)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    }
                                    .onMove(perform: canReorderLessons ? { source, destination in
                                        moveLessons(from: source, to: destination, in: groupLessons)
                                    } : nil)
                                }
                            }
                        }
                    }
                    .lessonsMiddleColumnListStyle()
                    .searchable(text: $filterState.searchText, placement: .toolbar)
                    .navigationTitle(subject)
                    .id("LessonList")
                }
            } else {
                ContentUnavailableView(
                    "Select an Album",
                    systemImage: "rectangle.stack",
                    description: Text("Select a subject from the sidebar to view lessons.")
                )
            }
        }
    }

    private var lessonDetailColumn: some View {
        Group {
            if let lesson = selectedLesson {
                LessonDetailView(lesson: lesson) { _ in
                    _ = saveCoordinator.save(modelContext, reason: "Edit Lesson")
                } onDone: {
                    selectedLesson = nil
                }
                .id(lesson.id)
            } else {
                ContentUnavailableView(
                    "No Lesson Selected",
                    systemImage: "doc.text",
                    description: Text("Select a lesson from the list to view details.")
                )
            }
        }
    }

    // MARK: - Reordering Logic

    private func syncReorderableGroups() {
        reorderableGroups = groupsForSelectedSubject
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        guard let subject = selectedSubject, subject.trimmed().isEmpty == false else { return }
        reorderableGroups.move(fromOffsets: source, toOffset: destination)
        FilterOrderStore.saveGroupOrder(reorderableGroups, for: subject)
        FilterOrderStore.resetCache()
    }

    private func moveLessons(from source: IndexSet, to destination: Int, in orderedSubset: [Lesson]) {
        var newOrder = orderedSubset
        newOrder.move(fromOffsets: source, toOffset: destination)
        for (idx, lesson) in newOrder.enumerated() {
            if lesson.orderInGroup != idx {
                lesson.orderInGroup = idx
            }
        }
        modelContext.safeSave()
    }
}

// MARK: - Middle column list style fix (prevents inset padding blowout in 4-pane layouts)

private extension View {
    @ViewBuilder
    func lessonsMiddleColumnListStyle() -> some View {
        #if os(macOS)
        // .inset adds extra horizontal padding that becomes problematic when the app's main sidebar is revealed.
        self
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
        #else
        self
            .listStyle(.inset)
        #endif
    }
}

// MARK: - Internal Components

private struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                if !lesson.subheading.isEmpty {
                    Text(lesson.subheading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
