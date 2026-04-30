// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

private let logger = Logger.lessons

// MARK: - LessonsRootView Panes Extension

extension LessonsRootView {

    // MARK: - Subjects Column (Left)

    /// Computes lesson counts per subject for display in the sidebar
    private var lessonCountsBySubject: [String: Int] {
        var counts: [String: Int] = [:]
        for lesson in lessons {
            let subject = lesson.subject.trimmed()
            if !subject.isEmpty {
                counts[subject, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of all story-format lessons
    private var storyLessonCount: Int {
        lessons.filter(\.isStory).count
    }

    var subjectsColumn: some View {
        List(selection: $listSelectedSubject) {
            Section {
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
            }

            ForEach(subjects, id: \.self) { subject in
                SubjectListRow(subject: subject, lessonCount: lessonCountsBySubject[subject] ?? 0)
                    .tag(subject)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Lessons Content Column (Middle)

    @ViewBuilder
    var lessonsContentColumn: some View {
        if selectedSubject == Self.parshasSentinel {
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
            let mapSubject: String? = (selectedSubject == Self.storiesSentinel) ? nil : selectedSubject
            LessonsScopeMapView(
                lessons: Array(lessons),
                selectedSubject: mapSubject,
                spine: Binding(
                    get: { mapSpine },
                    set: { mapSpineRaw = $0.rawValue }
                ),
                onSelectThread: { key in self.focusedThread = key }
            )
            .navigationTitle("Scope & Sequence")
        }
    }

    /// Switches from Map mode to Browse mode, focused on the lesson's subject and showing
    /// the lesson's detail. Used by the "View in Browse" action from a Map pill.
    private func showLessonInBrowse(_ lesson: CDLesson) {
        focusedThread = nil
        displayModeRaw = LessonsDisplayMode.browse.rawValue
        if !lesson.subject.trimmed().isEmpty {
            filterState.selectedSubject = lesson.subject
            listSelectedSubject = lesson.subject
        }
        selectedLessonDetail = lesson
    }

    /// Switches from any mode to Map mode, focused on the lesson's (subject, group) thread.
    /// Used by the "Locate in Map" action from Browse cards and Plan rows.
    func locateLessonInMap(_ lesson: CDLesson) {
        let subject = lesson.subject.trimmed()
        guard !subject.isEmpty else { return }
        // Locating in Map by subject is unambiguous; if the user is currently on the
        // Great Lesson spine, they'll still see the lesson's thread because the focus
        // view is keyed by (subject, group), not the spine.
        displayModeRaw = LessonsDisplayMode.map.rawValue
        focusedThread = ThreadKey(subject: subject, group: lesson.group)
        // Keep selectedLessonDetail as-is so the right pane continues to show the lesson.
        selectedLessonDetail = lesson
    }

    /// Returns the lessons that belong to a (subject, group) thread.
    /// An empty group string in the key denotes the synthetic "ungrouped" bucket.
    private func lessonsForThread(_ key: ThreadKey) -> [CDLesson] {
        let subjectKey = key.subject.trimmed().lowercased()
        let groupKey = key.group.trimmed().lowercased()
        let isUngroupedBucket = groupKey.isEmpty

        return lessons.filter { lesson in
            guard lesson.subject.trimmed().lowercased() == subjectKey else { return false }
            let lessonGroupTrimmed = lesson.group.trimmed().lowercased()
            if isUngroupedBucket {
                return lessonGroupTrimmed.isEmpty
            }
            return lessonGroupTrimmed == groupKey
        }
    }

    private var normalLessonsContentColumn: some View {
        let hasSearchText: Bool = !filterState.debouncedSearchText.trimmed().isEmpty
        let hasSubject: Bool = selectedSubject.map { !$0.trimmed().isEmpty } ?? false
        let shouldShowFilters: Bool = (hasSubject || hasSearchText) && displayMode == .browse
        let shouldShowLessons: Bool = hasSubject || hasSearchText
        let navTitle: String = selectedSubject == Self.storiesSentinel
            ? "All Stories"
            : (selectedSubject ?? "Lessons")

        return VStack(spacing: 0) {
            if shouldShowFilters {
                lessonsFilterBar
                Divider()
            }

            lessonsMainArea(shouldShowLessons: shouldShowLessons)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navTitle)
        .searchable(text: $filterState.searchText, placement: .toolbar)
    }

    @ViewBuilder
    private func lessonsMainArea(shouldShowLessons: Bool) -> some View {
        if shouldShowLessons {
            if displayMode == .browse {
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
            isManualMode: isJiggling,
            onTapLesson: { lesson in
                selectedLessonDetail = lesson
            },
            onReorder: isJiggling ? { _, fromIndex, toIndex, subset in
                moveLessonsInSubject(
                    from: IndexSet(integer: fromIndex),
                    to: toIndex > fromIndex ? toIndex + 1 : toIndex,
                    in: subset
                )
            } : nil,
            onGiveLesson: { lesson in
                lessonToSchedule = lesson
            },
            onActivateJiggle: {
                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isJiggling = true
                }
            },
            onLocateInMap: { lesson in
                locateLessonInMap(lesson)
            },
            statusCounts: statusCounts,
            selectedSubject: selectedSubject,
            selectedLessonID: selectedLessonDetail?.id,
            lastPresentedDates: lastPresentedDates,
            showIntroductionCards: !hasActiveFilters
        )
    }

    /// Lessons filtered by chip bar filters
    private var filteredLessonsForDisplay: [CDLesson] {
        var result = lessonsForSubject

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

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Select an Album",
            systemImage: "rectangle.stack",
            description: Text("Select a subject from the sidebar to view lessons.")
        )
    }

    // MARK: - Plan Mode List

    @ViewBuilder
    private var planModeList: some View {
        outlineView
    }

    // MARK: - Outline View

    private var outlineView: some View {
        let ungroupedLabel: String = "Ungrouped"
        let displayGroups: [String] = computeDisplayGroups(ungroupedLabel: ungroupedLabel)
        let lessonsByGroup: [String: [CDLesson]] = buildLessonsByGroup(displayGroups: displayGroups, ungroupedLabel: ungroupedLabel)
        let allSubheadings: [String: [String]] = buildSubheadings(displayGroups: displayGroups, lessonsByGroup: lessonsByGroup)

        return outlineViewContent(
            displayGroups: displayGroups,
            lessonsByGroup: lessonsByGroup,
            allSubheadings: allSubheadings
        )
    }

    private func buildLessonsByGroup(displayGroups: [String], ungroupedLabel: String) -> [String: [CDLesson]] {
        var result: [String: [CDLesson]] = [:]
        for group in displayGroups {
            result[group] = lessonsForGroup(group, ungroupedLabel: ungroupedLabel)
        }
        return result
    }

    private func buildSubheadings(displayGroups: [String], lessonsByGroup: [String: [CDLesson]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for group in displayGroups {
            let groupLessons: [CDLesson] = lessonsByGroup[group] ?? []
            let subs: [String] = Array(Set(groupLessons.map { $0.subheading.trimmed() }.filter { !$0.isEmpty }))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if !subs.isEmpty {
                result[group] = subs
            }
        }
        return result
    }

    private func outlineViewContent(
        displayGroups: [String],
        lessonsByGroup: [String: [CDLesson]],
        allSubheadings: [String: [String]]
    ) -> some View {
        LessonsOutlineView(
            subject: selectedSubject ?? "",
            displayGroups: displayGroups,
            lessonsByGroup: lessonsByGroup,
            allSubheadings: allSubheadings,
            selectedLessonID: selectedLessonDetail?.id,
            isJiggling: isJiggling,
            onSelectLesson: { selectedLessonDetail = $0 },
            onScheduleLesson: { lessonToSchedule = $0 },
            onMoveToGroup: { moveLessonToGroup(lesson: $0, newGroup: $1) },
            onMoveToSubheading: { moveLessonToSubheading(lesson: $0, newSubheading: $1) },
            onReorderSubheadings: { handleReorderSubheadings($0) },
            onConfigureTrack: { handleConfigureTrack($0) },
            onActivateJiggle: { handleActivateJiggle() },
            onMoveLessonsInGroup: { source, destination, group in
                let groupLessons = lessonsForGroup(group, ungroupedLabel: "Ungrouped")
                moveLessonsInSubject(from: source, to: destination, in: groupLessons)
            },
            onMoveGroups: { moveGroups(from: $0, to: $1, in: displayGroups) },
            onMoveLessonIDToGroup: { handleMoveLessonIDToGroup($0, targetGroup: $1) },
            onLocateInMap: { lesson in locateLessonInMap(lesson) }
        )
    }

    private func handleReorderSubheadings(_ group: String) {
        if let subject = selectedSubject {
            reorderSubheadingsItem = SubheadingReorderItem(subject: subject, group: group)
        }
    }

    private func handleConfigureTrack(_ group: String) {
        if let subject = selectedSubject {
            trackSettingsItem = TrackSettingsItem(subject: subject, group: group)
        }
    }

    private func handleActivateJiggle() {
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isJiggling = true
        }
    }

    private func handleMoveLessonIDToGroup(_ lessonID: UUID, targetGroup: String) {
        if let lesson = lessonsForSubject.first(where: { $0.id == lessonID }) {
            moveLessonToGroup(lesson: lesson, newGroup: targetGroup)
        }
    }

    /// Computes the ordered display groups from reorderableGroups or fresh data.
    private func computeDisplayGroups(ungroupedLabel: String) -> [String] {
        let baseGroups = groupsFromFilteredLessons
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

        if reorderableGroups.isEmpty {
            return allGroups
        }
        let existingSet = Set(reorderableGroups)
        let missing = allGroups.filter { !existingSet.contains($0) }
        return reorderableGroups.filter { allGroups.contains($0) } + missing
    }

    /// Returns sorted lessons for a specific group
    func lessonsForGroup(_ group: String, ungroupedLabel: String) -> [CDLesson] {
        lessonsForSubject.filter { lesson in
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

}
