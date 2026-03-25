// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import SwiftData
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

    var lessonsContentColumn: some View {
        VStack(spacing: 0) {
            // Filter chip bar (only show when a subject is selected or searching)
            let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
            let shouldShowFilters = (selectedSubject.map { !$0.trimmed().isEmpty } ?? false) || hasSearchText

            if shouldShowFilters && displayMode == .browse {
                LessonsFilterChipBar(
                    sourceFilter: $filterState.sourceFilter,
                    personalKindFilter: $filterState.personalKindFilter,
                    formatFilter: $filterState.formatFilter,
                    hasAttachmentFilter: $filterState.hasAttachmentFilter,
                    needsAttentionFilter: $filterState.needsAttentionFilter
                )

                Divider()
            }

            // Main content
            Group {
                let shouldShowLessons = (selectedSubject.map { !$0.trimmed().isEmpty } ?? false) || hasSearchText

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(
            selectedSubject == Self.storiesSentinel ? "All Stories" : (selectedSubject ?? "Lessons")
        )
        .searchable(text: $filterState.searchText, placement: .toolbar)
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
                _ = adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isJiggling = true
                }
            },
            statusCounts: statusCounts,
            selectedSubject: selectedSubject,
            selectedLessonID: selectedLessonDetail?.id,
            lastPresentedDates: lastPresentedDates,
            showIntroductionCards: !hasActiveFilters
        )
    }

    /// Lessons filtered by chip bar filters
    private var filteredLessonsForDisplay: [Lesson] {
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
            result = result.filter { counts[$0.id, default: 0] > 0 }
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
        let ungroupedLabel = "Ungrouped"

        let displayGroups: [String] = computeDisplayGroups(ungroupedLabel: ungroupedLabel)

        var lessonsByGroup: [String: [Lesson]] = [:]
        for group in displayGroups {
            lessonsByGroup[group] = lessonsForGroup(group, ungroupedLabel: ungroupedLabel)
        }

        var allSubheadings: [String: [String]] = [:]
        for group in displayGroups {
            let groupLessons = lessonsByGroup[group] ?? []
            let subs = Array(Set(groupLessons.map { $0.subheading.trimmed() }.filter { !$0.isEmpty }))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if !subs.isEmpty {
                allSubheadings[group] = subs
            }
        }

        return LessonsOutlineView(
            subject: selectedSubject ?? "",
            displayGroups: displayGroups,
            lessonsByGroup: lessonsByGroup,
            allSubheadings: allSubheadings,
            selectedLessonID: selectedLessonDetail?.id,
            isJiggling: isJiggling,
            onSelectLesson: { lesson in
                selectedLessonDetail = lesson
            },
            onScheduleLesson: { lesson in
                lessonToSchedule = lesson
            },
            onMoveToGroup: { lesson, targetGroup in
                moveLessonToGroup(lesson: lesson, newGroup: targetGroup)
            },
            onMoveToSubheading: { lesson, targetSh in
                moveLessonToSubheading(lesson: lesson, newSubheading: targetSh)
            },
            onReorderSubheadings: { group in
                if let subject = selectedSubject {
                    reorderSubheadingsItem = SubheadingReorderItem(subject: subject, group: group)
                }
            },
            onConfigureTrack: { group in
                if let subject = selectedSubject {
                    trackSettingsItem = TrackSettingsItem(subject: subject, group: group)
                }
            },
            onActivateJiggle: {
                _ = adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isJiggling = true
                }
            },
            onMoveLessonsInGroup: { source, destination, group in
                let groupLessons = lessonsForGroup(group, ungroupedLabel: "Ungrouped")
                moveLessonsInSubject(from: source, to: destination, in: groupLessons)
            },
            onMoveGroups: { source, destination in
                moveGroups(from: source, to: destination, in: displayGroups)
            },
            onMoveLessonIDToGroup: { lessonID, targetGroup in
                if let lesson = lessonsForSubject.first(where: { $0.id == lessonID }) {
                    moveLessonToGroup(lesson: lesson, newGroup: targetGroup)
                }
            }
        )
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
    func lessonsForGroup(_ group: String, ungroupedLabel: String) -> [Lesson] {
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
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Lesson Detail Pane (Right)

    func lessonDetailPane(lesson: Lesson) -> some View {
        LessonDetailView(
            lesson: lesson,
            allLessons: lessons,
            onSave: { _ in
                saveCoordinator.save(modelContext, reason: "Update lesson")
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

}
