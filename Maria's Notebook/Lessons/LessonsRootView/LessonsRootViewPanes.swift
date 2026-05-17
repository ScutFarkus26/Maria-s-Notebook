// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

private let logger = Logger.lessons

// MARK: - LessonsRootView Panes Extension

extension LessonsRootView {

    // MARK: - Areas Column (Left)

    /// Computes lesson counts per area for display in the sidebar
    private var lessonCountsByArea: [String: Int] {
        var counts: [String: Int] = [:]
        for lesson in lessons {
            let area = lesson.area.trimmed()
            if !area.isEmpty {
                counts[area, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of all story-format lessons
    private var storyLessonCount: Int {
        lessons.filter(\.isStory).count
    }

    var areasColumn: some View {
        List(selection: $listSelectedArea) {
            Section {
                Label {
                    Text("All Lessons")
                } icon: {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.blue)
                }
                .tag(Self.allLessonsSentinel)

                Label {
                    HStack {
                        Text("All Stories")
                        Spacer()
                        if storyLessonCount > 0 {
                            Text("\(storyLessonCount)")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "book.pages")
                        .foregroundStyle(.purple)
                }
                .tag(Self.storiesSentinel)

                Label {
                    HStack {
                        Text("Parshas")
                        Spacer()
                    }
                } icon: {
                    Image(systemName: "scroll")
                        .foregroundStyle(.indigo)
                }
                .tag(Self.parshasSentinel)
            }

            Section("Areas") {
                ForEach(areas, id: \.self) { area in
                    AreaListRow(area: area, lessonCount: lessonCountsByArea[area] ?? 0)
                        .tag(area)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Lessons Content Column (Middle)

    @ViewBuilder
    var lessonsContentColumn: some View {
        if selectedArea == Self.parshasSentinel {
            ParshaBrowseView { lesson in
                selectedLessonDetail = lesson
            }
        } else if displayMode == .map {
            mapModeColumn
        } else {
            normalLessonsContentColumn
        }
    }

    // MARK: - Map Mode Column

    @ViewBuilder
    private var mapModeColumn: some View {
        if let focusedThread {
            let lessonsInThread: [CDLesson] = lessonsForThread(focusedThread)
            LessonsScopeThreadFocusView(
                threadKey: focusedThread,
                lessons: lessonsInThread,
                onBack: { self.focusedThread = nil },
                onSelectLesson: { lesson in selectedLessonDetail = lesson },
                onShowInBrowse: { lesson in showLessonInBrowse(lesson) }
            )
            .navigationTitle(focusedThread.displayName)
        } else {
            let mapArea: String? = (selectedArea == Self.storiesSentinel) ? nil : selectedArea
            LessonsScopeMapView(
                lessons: Array(lessons),
                selectedArea: mapArea,
                spine: Binding(
                    get: { mapSpine },
                    set: { mapSpineRaw = $0.rawValue }
                ),
                onSelectThread: { key in self.focusedThread = key }
            )
            .navigationTitle("Scope & Sequence")
        }
    }

    /// Switches from Map mode to Browse mode, focused on the lesson's area and showing
    /// the lesson's detail. Used by the "View in Browse" action from a Map pill.
    private func showLessonInBrowse(_ lesson: CDLesson) {
        focusedThread = nil
        displayModeRaw = LessonsDisplayMode.browse.rawValue
        if !lesson.area.trimmed().isEmpty {
            filterState.selectedArea = lesson.area
            listSelectedArea = lesson.area
        }
        selectedLessonDetail = lesson
    }

    /// Switches from any mode to Map mode, focused on the lesson's (area, sequence) thread.
    /// Used by the "Locate in Map" action from Browse cards and Plan rows.
    func locateLessonInMap(_ lesson: CDLesson) {
        let area = lesson.area.trimmed()
        guard !area.isEmpty else { return }
        // Locating in Map by area is unambiguous; if the user is currently on the
        // Great Lesson spine, they'll still see the lesson's thread because the focus
        // view is keyed by (area, sequence), not the spine.
        displayModeRaw = LessonsDisplayMode.map.rawValue
        focusedThread = ThreadKey(area: area, sequence: lesson.sequence)
        // Keep selectedLessonDetail as-is so the right pane continues to show the lesson.
        selectedLessonDetail = lesson
    }

    /// Returns the lessons that belong to a (area, sequence) thread.
    /// An empty sequence string in the key denotes the synthetic "ungrouped" bucket.
    private func lessonsForThread(_ key: ThreadKey) -> [CDLesson] {
        let areaKey = key.area.trimmed().lowercased()
        let sequenceKey = key.sequence.trimmed().lowercased()
        let isUngroupedBucket = sequenceKey.isEmpty

        return lessons.filter { lesson in
            guard lesson.area.trimmed().lowercased() == areaKey else { return false }
            let lessonSequenceTrimmed = lesson.sequence.trimmed().lowercased()
            if isUngroupedBucket {
                return lessonSequenceTrimmed.isEmpty
            }
            return lessonSequenceTrimmed == sequenceKey
        }
    }

    private var normalLessonsContentColumn: some View {
        let hasSearchText: Bool = !filterState.debouncedSearchText.trimmed().isEmpty
        let isAllLessons: Bool = selectedArea == Self.allLessonsSentinel
        let hasArea: Bool = selectedArea.map { !$0.trimmed().isEmpty } ?? false
        let shouldShowFilters: Bool = hasArea || hasSearchText || isAllLessons
        let shouldShowLessons: Bool = hasArea || hasSearchText || isAllLessons
        let navTitle: String = {
            if selectedArea == Self.storiesSentinel { return "All Stories" }
            if selectedArea == Self.allLessonsSentinel { return "All Lessons" }
            return selectedArea ?? "Lessons"
        }()

        return VStack(spacing: 0) {
            if shouldShowFilters {
                lessonsFilterBar
                Divider()
            }

            lessonsMainArea(shouldShowLessons: shouldShowLessons, hasSearchText: hasSearchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navTitle)
    }

    @ViewBuilder
    private func lessonsMainArea(shouldShowLessons: Bool, hasSearchText: Bool) -> some View {
        if shouldShowLessons {
            if hasSearchText {
                LessonsSearchResultsView(
                    lessons: filteredLessonsForDisplay,
                    statusCounts: statusCounts,
                    lastPresentedDates: lastPresentedDates,
                    selectedLessonID: selectedLessonDetail?.id,
                    onSelectLesson: { selectedLessonDetail = $0 },
                    onScheduleLesson: { lessonToSchedule = $0 }
                )
            } else if displayMode == .browse {
                browseModeLessons
            } else {
                planModeList
            }
        } else {
            emptyStateView
        }
    }

    private var lessonsFilterBar: some View {
        LessonsFilterChipBar(
            sourceFilter: $filterState.sourceFilter,
            personalKindFilter: $filterState.personalKindFilter,
            formatFilter: $filterState.formatFilter,
            hasAttachmentFilter: $filterState.hasAttachmentFilter,
            needsAttentionFilter: $filterState.needsAttentionFilter
        )
    }

    private var browseModeLessons: some View {
        LessonsCardsGridView(
            lessons: filteredLessonsForDisplay,
            onTapLesson: { lesson in
                selectedLessonDetail = lesson
            },
            onGiveLesson: { lesson in
                lessonToSchedule = lesson
            },
            onReorderInOutline: { lesson in
                switchToOutlineMode(focusing: lesson)
            },
            onLocateInMap: { lesson in
                locateLessonInMap(lesson)
            },
            statusCounts: statusCounts,
            selectedArea: selectedArea,
            selectedLessonID: selectedLessonDetail?.id,
            lastPresentedDates: lastPresentedDates,
            showIntroductionCards: !hasActiveFilters
        )
    }

    /// Switches to Outline mode (formerly Plan), preserving the area so the
    /// user can drag-reorder the lesson they just right-clicked on a Browse card.
    func switchToOutlineMode(focusing lesson: CDLesson) {
        let area = lesson.area.trimmed()
        if !area.isEmpty {
            filterState.selectedArea = area
            listSelectedArea = area
        }
        displayModeRaw = LessonsDisplayMode.outline.rawValue
    }

    /// Lessons filtered by chip bar filters
    private var filteredLessonsForDisplay: [CDLesson] {
        var result = lessonsForArea

        // Source filter
        if let source = filterState.sourceFilter {
            result = result.filter { $0.source == source }
        }

        // Personal kind filter
        if let kind = filterState.personalKindFilter {
            result = result.filter { $0.personalKind == kind }
        }

        // Has attachment filter
        if filterState.hasAttachmentFilter {
            result = result.filter { $0.pagesFileBookmark != nil || $0.pagesFileRelativePath != nil }
        }

        // Needs attention filter (status count > 0)
        if filterState.needsAttentionFilter, let counts = statusCounts {
            result = result.filter { guard let id = $0.id else { return false }; return counts[id, default: 0] > 0 }
        }

        return result
    }

    /// Whether any chip bar filters are active (used to hide introductions when filtering)
    private var hasActiveFilters: Bool {
        filterState.sourceFilter != nil ||
        filterState.personalKindFilter != nil ||
        filterState.hasAttachmentFilter ||
        filterState.needsAttentionFilter
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if areas.isEmpty {
            ContentUnavailableView {
                Label("No Lessons Yet", systemImage: "rectangle.stack")
            } description: {
                Text("Add lessons from your training album, or create your own. Each area groups the lessons you give from that album.")
            } actions: {
                Button {
                    showingAddLesson = true
                } label: {
                    Label("Add Your First Lesson", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "Select a Area",
                systemImage: "rectangle.stack",
                description: Text("Choose a area from the sidebar to browse its lessons.")
            )
        }
    }

    // MARK: - Plan Mode List

    @ViewBuilder
    private var planModeList: some View {
        outlineView
    }

    // MARK: - Outline View

    private var outlineView: some View {
        let ungroupedLabel: String = "Ungrouped"
        let displaySequences: [String] = computeDisplaySequences(ungroupedLabel: ungroupedLabel)
        let lessonsBySequence: [String: [CDLesson]] = buildLessonsBySequence(displaySequences: displaySequences, ungroupedLabel: ungroupedLabel)
        let allSections: [String: [String]] = buildSections(displaySequences: displaySequences, lessonsBySequence: lessonsBySequence)

        return outlineViewContent(
            displaySequences: displaySequences,
            lessonsBySequence: lessonsBySequence,
            allSections: allSections,
            isEditing: canReorderInOutlineMode
        )
    }

    private func buildLessonsBySequence(displaySequences: [String], ungroupedLabel: String) -> [String: [CDLesson]] {
        var result: [String: [CDLesson]] = [:]
        for sequence in displaySequences {
            result[sequence] = lessonsForSequence(sequence, ungroupedLabel: ungroupedLabel)
        }
        return result
    }

    private func buildSections(displaySequences: [String], lessonsBySequence: [String: [CDLesson]]) -> [String: [String]] {
        _ = sectionOrderRevision
        let area: String = selectedArea ?? ""
        var result: [String: [String]] = [:]
        for sequence in displaySequences {
            let groupLessons: [CDLesson] = lessonsBySequence[sequence] ?? []
            let existing: [String] = Array(Set(groupLessons.map { $0.section.trimmed() }.filter { !$0.isEmpty }))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            guard !existing.isEmpty else { continue }
            if area.trimmed().isEmpty {
                result[sequence] = existing
            } else {
                result[sequence] = FilterOrderStore.loadSectionOrder(for: area, sequence: sequence, existing: existing)
            }
        }
        return result
    }

    private func outlineViewContent(
        displaySequences: [String],
        lessonsBySequence: [String: [CDLesson]],
        allSections: [String: [String]],
        isEditing: Bool
    ) -> some View {
        LessonsOutlineView(
            area: selectedArea ?? "",
            displaySequences: displaySequences,
            lessonsBySequence: lessonsBySequence,
            allSections: allSections,
            selectedLessonID: selectedLessonDetail?.id,
            isEditing: isEditing,
            onSelectLesson: { selectedLessonDetail = $0 },
            onScheduleLesson: { lessonToSchedule = $0 },
            onMoveToSequence: { moveLessonToSequence(lesson: $0, newSequence: $1) },
            onMoveToSection: { moveLessonToSection(lesson: $0, newSection: $1) },
            onReorderSections: { handleReorderSections($0) },
            onReorderSectionByDrag: { sequence, source, target in
                reorderSectionByDrag(sequence: sequence, source: source, target: target)
            },
            onConfigureTrack: { handleConfigureTrack($0) },
            onMoveLessonsInSequence: { source, destination, sequence in
                let groupLessons = lessonsForSequence(sequence, ungroupedLabel: "Ungrouped")
                moveLessonsInArea(from: source, to: destination, in: groupLessons)
            },
            onMoveSequences: { moveSequences(from: $0, to: $1, in: displaySequences) },
            onMoveLessonIDToSequence: { handleMoveLessonIDToSequence($0, targetSequence: $1) },
            onLocateInMap: { lesson in locateLessonInMap(lesson) }
        )
    }

    private func handleReorderSections(_ sequence: String) {
        if let area = selectedArea {
            reorderSectionsItem = SectionReorderItem(area: area, sequence: sequence)
        }
    }

    private func handleConfigureTrack(_ sequence: String) {
        if let area = selectedArea {
            trackSettingsItem = TrackSettingsItem(area: area, sequence: sequence)
        }
    }

    private func handleMoveLessonIDToSequence(_ lessonID: UUID, targetSequence: String) {
        if let lesson = lessonsForArea.first(where: { $0.id == lessonID }) {
            moveLessonToSequence(lesson: lesson, newSequence: targetSequence)
        }
    }

    /// Computes the ordered display groups from reorderableSequences or fresh data.
    private func computeDisplaySequences(ungroupedLabel: String) -> [String] {
        let baseSequences = groupsFromFilteredLessons
        let hasUngrouped = lessonsForArea.contains { $0.sequence.trimmed().isEmpty }
        let allSequences = hasUngrouped ? (baseSequences + [ungroupedLabel]) : baseSequences

        if reorderableSequences.isEmpty {
            return allSequences
        }
        let existingSet = Set(reorderableSequences)
        let missing = allSequences.filter { !existingSet.contains($0) }
        return reorderableSequences.filter { allSequences.contains($0) } + missing
    }

    /// Returns sorted lessons for a specific sequence
    func lessonsForSequence(_ sequence: String, ungroupedLabel: String) -> [CDLesson] {
        lessonsForArea.filter { lesson in
            let lessonSequenceTrimmed = lesson.sequence.trimmed()
            if sequence == ungroupedLabel {
                return lessonSequenceTrimmed.isEmpty
            } else {
                return lessonSequenceTrimmed.caseInsensitiveCompare(sequence.trimmed()) == .orderedSame
            }
        }.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence {
                return lhs.orderInSequence < rhs.orderInSequence
            }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    // MARK: - CDLesson Detail Pane (Right)

    func lessonDetailPane(lesson: CDLesson) -> some View {
        LessonDetailView(
            lesson: lesson,
            allLessons: Array(lessons),
            onSave: { _ in
                saveCoordinator.save(viewContext, reason: "Update lesson")
            },
            onDone: {
                selectedLessonDetail = nil
            },
            onLocateInMap: { lesson in
                locateLessonInMap(lesson)
            },
            onLocateInSequence: { lesson in
                switchToOutlineMode(focusing: lesson)
            },
            onSchedule: { lesson in
                lessonToSchedule = lesson
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.paneBackground)
    }

}
