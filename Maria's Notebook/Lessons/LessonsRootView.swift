// Maria's Notebook/Lessons/LessonsRootView.swift

import SwiftUI
import SwiftData

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

struct LessonsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // Data
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex), SortDescriptor(\Lesson.orderInGroup)])
    private var lessons: [Lesson]

    // UI state
    @StateObject private var filterState = LessonsFilterState()

    // Selection - pure UI state, no SwiftData writes from body
    // Intermediate state for List selection to avoid publishing during view updates
    @State private var listSelectedSubject: String? = nil

    @SceneStorage("Lessons.selectedSubject") private var selectedSubjectRaw: String = ""
    @SceneStorage("Lessons.searchText") private var searchTextRaw: String = ""
    @SceneStorage("Lessons.displayMode") private var displayModeRaw: String = LessonsDisplayMode.browse.rawValue
    
    // Schedule presentation state
    @State private var lessonToSchedule: Lesson?
    
    // Track settings state
    @State private var trackSettingsItem: TrackSettingsItem?
    
    // Lesson detail sidebar state
    @State private var selectedLessonDetail: Lesson?
    
    // Sheet presentation state
    @State private var showingAddLesson = false
    @State private var showingBulkEntry = false
    
    // Display mode
    private var displayMode: LessonsDisplayMode {
        LessonsDisplayMode(rawValue: displayModeRaw) ?? .browse
    }
    
    // Migration flag
    @AppStorage("Lessons.sortIndexMigrated") private var sortIndexMigrated: Bool = false

    // Local state for responsive reordering
    @State private var reorderableGroups: [String] = []
    
    // Group organization mode
    @State private var isOrganizingGroups: Bool = false

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
    
    // Groups from the filtered lessons (used when searching across all subjects)
    private var groupsFromFilteredLessons: [String] {
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        if hasSearchText {
            // When searching, get unique groups from all filtered lessons
            let unique = Set(lessonsForSubject.map { $0.group.trimmed() }.filter { !$0.isEmpty })
            return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            // When not searching, use subject-based groups
            return groupsForSelectedSubject
        }
    }

    // Filtered lessons for the entire subject (all groups)
    // When searching, ignore subject filter to search across all lessons
    private var lessonsForSubject: [Lesson] {
        let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
        return helper.filteredLessons(
            modelContext: modelContext,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: filterState.debouncedSearchText,
            selectedSubject: hasSearchText ? nil : filterState.selectedSubject,
            selectedGroup: nil // We want ALL groups for the subject, displayed inline
        )
    }
    
    private var canReorderInPlanMode: Bool {
        displayMode == .plan &&
        filterState.debouncedSearchText.trimmed().isEmpty &&
        (filterState.selectedSubject?.trimmed().isEmpty == false)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left pane: Subject selector
            subjectsColumn
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
            
            Divider()
            
            // Middle pane: Lessons grid or list based on mode
            lessonsContentColumn
                .frame(minWidth: 300)
            
            // Right pane: Lesson detail (slides in when lesson is selected)
            if let selectedLesson = selectedLessonDetail {
                Divider()
                lessonDetailPane(lesson: selectedLesson)
                    .frame(width: 520)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedLessonDetail?.id)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task {
            await MainActor.run {
                // Migrate sortIndex if needed
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
                syncReorderableGroups()
            }
        }
        .onChange(of: isOrganizingGroups) { _, newValue in
            if newValue {
                syncReorderableGroups()
            }
        }
        .onChange(of: filterState.searchText) { _, newValue in
            Task { @MainActor in
                searchTextRaw = newValue
            }
        }
        .onChange(of: displayMode) { _, newValue in
            Task { @MainActor in
                displayModeRaw = newValue.rawValue
                // Exit organize mode when switching away from plan mode
                if newValue != .plan {
                    isOrganizingGroups = false
                }
                #if os(iOS)
                editMode = (newValue == .plan) ? .active : .inactive
                #endif
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Mode switcher
                Picker("Display Mode", selection: Binding(
                    get: { displayMode },
                    set: { displayModeRaw = $0.rawValue }
                )) {
                    ForEach(LessonsDisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .disabled(selectedSubject == nil)
                
                // Organize Groups button (only in plan mode)
                if displayMode == .plan && selectedSubject != nil {
                    Button {
                        isOrganizingGroups.toggle()
                    } label: {
                        Label(isOrganizingGroups ? "Done Organizing" : "Organize Groups", 
                              systemImage: isOrganizingGroups ? "checkmark.circle.fill" : "list.bullet.indent")
                    }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
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
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $lessonToSchedule) { lesson in
            SchedulePresentationSheet(
                lesson: lesson,
                onPlan: { studentIDs in
                    planPresentation(for: lesson, studentIDs: studentIDs)
                },
                onCancel: {
                    lessonToSchedule = nil
                }
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

    // MARK: - Panes

    private var subjectsColumn: some View {
        List(selection: $listSelectedSubject) {
            ForEach(subjects, id: \.self) { subject in
                Text(subject)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .tag(subject)
            }
        }
        .listStyle(.sidebar)
    }

    private var lessonsContentColumn: some View {
        Group {
            let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
            let shouldShowLessons = (selectedSubject != nil && !selectedSubject!.trimmed().isEmpty) || hasSearchText
            
            if shouldShowLessons {
                if displayMode == .browse {
                    // Browse mode: Grid view (no reordering)
                    LessonsCardsGridView(
                        lessons: lessonsForSubject,
                        isManualMode: false,
                        onTapLesson: { lesson in
                            selectedLessonDetail = lesson
                        },
                        onReorder: nil,
                        onGiveLesson: { lesson in
                            lessonToSchedule = lesson
                        },
                        selectedSubject: selectedSubject
                    )
                } else {
                    // Plan mode: List view with reordering
                    planModeList
                }
            } else {
                ContentUnavailableView(
                    "Select an Album",
                    systemImage: "rectangle.stack",
                    description: Text("Select a subject from the sidebar to view lessons.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(selectedSubject ?? "Lessons")
        .searchable(text: $filterState.searchText, placement: .toolbar)
    }
    
    @ViewBuilder
    private var planModeList: some View {
        if isOrganizingGroups {
            organizeGroupsView
        } else {
            expandedGroupsView
        }
    }
    
    private var organizeGroupsView: some View {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsFromFilteredLessons
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
        
        // Ensure displayGroups includes all current groups, using saved order from reorderableGroups
        // Start with reorderableGroups (which should be synced when entering organize mode)
        // and add any missing groups at the end
        let displayGroups: [String] = {
            if reorderableGroups.isEmpty {
                return allGroups
            }
            let existingSet = Set(reorderableGroups)
            let missing = allGroups.filter { !existingSet.contains($0) }
            return reorderableGroups + missing
        }()
        
        return List {
            ForEach(displayGroups, id: \.self) { group in
                HStack(spacing: 12) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    
                    Text(group)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    
                    Spacer()
                    
                    // Show lesson count
                    let groupLessons = lessonsForSubject.filter { lesson in
                        let lessonGroupTrimmed = lesson.group.trimmed()
                        if group == ungroupedLabel {
                            return lessonGroupTrimmed.isEmpty
                        } else {
                            return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
                        }
                    }
                    
                    Text("\(groupLessons.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            .onMove { source, destination in
                moveGroups(from: source, to: destination, in: displayGroups)
            }
        }
        .listStyle(.plain)
        .id("OrganizeGroupsList")
    }
    
    private var expandedGroupsView: some View {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsFromFilteredLessons
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let displayGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
        
        return List {
            ForEach(displayGroups, id: \.self) { group in
                let groupLessons = lessonsForSubject.filter { lesson in
                    let lessonGroupTrimmed = lesson.group.trimmed()
                    if group == ungroupedLabel {
                        return lessonGroupTrimmed.isEmpty
                    } else {
                        return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
                    }
                }.sorted { lhs, rhs in
                    if lhs.sortIndex != rhs.sortIndex {
                        return lhs.sortIndex < rhs.sortIndex
                    }
                    if lhs.orderInGroup != rhs.orderInGroup {
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

                if !groupLessons.isEmpty {
                    Section(header: groupSectionHeader(group: group, subject: selectedSubject ?? "")) {
                        ForEach(groupLessons, id: \.self) { lesson in
                            HStack(spacing: 12) {
                                // Drag handle (visible in Plan mode)
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                                
                                LessonRow(lesson: lesson, secondaryTextStyle: .subheading, showTagIcon: false)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .contextMenu {
                                Button {
                                    selectedLessonDetail = lesson
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }
                                Button {
                                    lessonToSchedule = lesson
                                } label: {
                                    Label("Plan Presentation", systemImage: "tray.and.arrow.down")
                                }
                            }
                            .onTapGesture {
                                selectedLessonDetail = lesson
                            }
                        }
                        .onMove(perform: canReorderInPlanMode ? { source, destination in
                            moveLessonsInSubject(from: source, to: destination, in: groupLessons)
                        } : nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .id("PlanModeList")
    }
    
    // MARK: - Lesson Detail Pane
    
    private func lessonDetailPane(lesson: Lesson) -> some View {
        LessonDetailView(
            lesson: lesson,
            onSave: { updatedLesson in
                _ = saveCoordinator.save(modelContext, reason: "Update lesson")
            },
            onDone: {
                selectedLessonDetail = nil
            }
        )
        .frame(width: 520)
        .frame(maxHeight: .infinity)
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
    }

    // MARK: - Reordering Logic

    private func syncReorderableGroups() {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsForSelectedSubject
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
        
        // Load saved order if available, otherwise use current order
        if let subject = selectedSubject, !subject.trimmed().isEmpty {
            let orderedGroups = FilterOrderStore.loadGroupOrder(for: subject, existing: baseGroups)
            let orderedWithUngrouped = hasUngrouped ? (orderedGroups + [ungroupedLabel]) : orderedGroups
            reorderableGroups = orderedWithUngrouped
        } else {
            reorderableGroups = allGroups
        }
    }
    
    @MainActor
    private func moveGroups(from source: IndexSet, to destination: Int, in groups: [String]) {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groups.count else { return }
        
        // Reorder groups
        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)
        
        // Update state
        reorderableGroups = reordered
        
        // Save to FilterOrderStore (excluding "Ungrouped" label)
        let ungroupedLabel = "Ungrouped"
        let groupsToSave = reordered.filter { $0 != ungroupedLabel }
        FilterOrderStore.saveGroupOrder(groupsToSave, for: subject)
        FilterOrderStore.resetCache()
    }

    @MainActor
    private func moveLessonsInSubject(from source: IndexSet, to destination: Int, in groupLessons: [Lesson]) {
        guard canReorderInPlanMode else { return }
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groupLessons.count else { return }
        
        // Reorder within the group
        var reorderedGroup = groupLessons
        reorderedGroup.move(fromOffsets: source, toOffset: destination)
        
        // Update orderInGroup for this group
        for (idx, lesson) in reorderedGroup.enumerated() {
            lesson.orderInGroup = idx
        }
        
        // Get all lessons in the subject, sorted by group order then orderInGroup
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsForSelectedSubject
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let displayGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
        
        var allLessonsInOrder: [Lesson] = []
        for group in displayGroups {
            let groupLessons = lessonsForSubject.filter { lesson in
                let lessonGroupTrimmed = lesson.group.trimmed()
                if group == ungroupedLabel {
                    return lessonGroupTrimmed.isEmpty
                } else {
                    return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
                }
            }.sorted { lhs, rhs in
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            allLessonsInOrder.append(contentsOf: groupLessons)
        }
        
        // Update sortIndex for all lessons in the subject based on the new order
        for (idx, lesson) in allLessonsInOrder.enumerated() {
            lesson.sortIndex = idx
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to save lesson reorder: \(error)")
        }
    }
    
    // MARK: - Plan Presentation
    
    private func planPresentation(for lesson: Lesson, studentIDs: Set<UUID>) {
        guard !studentIDs.isEmpty else { return }
        
        // Fetch students
        let studentUUIDs = Array(studentIDs)
        let predicate = #Predicate<Student> { studentUUIDs.contains($0.id) }
        let descriptor = FetchDescriptor<Student>(predicate: predicate)
        let students = (try? modelContext.fetch(descriptor)) ?? []
        
        // Check if an unscheduled StudentLesson already exists for this lesson+students combination
        let lessonIDString = lesson.id.uuidString
        let existingPredicate = #Predicate<StudentLesson> { sl in
            sl.lessonID == lessonIDString &&
            sl.scheduledFor == nil &&
            sl.givenAt == nil
        }
        let existingDescriptor = FetchDescriptor<StudentLesson>(predicate: existingPredicate)
        let existingLessons = (try? modelContext.fetch(existingDescriptor)) ?? []
        
        // Check if there's an exact match (same students)
        let studentSet = Set(studentUUIDs)
        if existingLessons.contains(where: { Set($0.resolvedStudentIDs) == studentSet }) {
            // Already exists, don't create duplicate
            lessonToSchedule = nil
            return
        }
        
        // Create new unscheduled StudentLesson (will appear in presentations inbox)
        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: studentUUIDs,
            createdAt: Date(),
            scheduledFor: nil, // nil = unscheduled, goes to inbox
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = students
        newStudentLesson.lesson = lesson
        
        modelContext.insert(newStudentLesson)
        _ = saveCoordinator.save(modelContext, reason: "Plan presentation")
        
        lessonToSchedule = nil
    }
    
    // MARK: - Group Track Settings
    
    @ViewBuilder
    private func groupSectionHeader(group: String, subject: String) -> some View {
        let iconName: String = {
            // All groups are tracks by default (sequential) unless explicitly disabled
            if GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                // Get effective track settings (returns default if no record exists)
                if let settings = try? GroupTrackService.getEffectiveTrackSettings(
                    subject: subject,
                    group: group,
                    modelContext: modelContext
                ) {
                    return settings.isSequential ? "list.number" : "list.bullet"
                }
                // Fallback to sequential if we can't determine (default behavior)
                return "list.number"
            }
            // Explicitly disabled - show non-track icon
            return "list.bullet.clipboard"
        }()
        
        HStack {
            Text(group)
            Spacer()
            Button {
                trackSettingsItem = TrackSettingsItem(subject: subject, group: group)
            } label: {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Configure track settings")
        }
    }
}
