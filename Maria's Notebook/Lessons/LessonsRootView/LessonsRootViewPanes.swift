// swiftlint:disable file_length
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

    var subjectsColumn: some View {
        List(selection: $listSelectedSubject) {
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
        .navigationTitle(selectedSubject ?? "Lessons")
        .searchable(text: $filterState.searchText, placement: .toolbar)
    }

    private var browseModeLessons: some View {
        LessonsCardsGridView(
            lessons: filteredLessonsForDisplay,
            isManualMode: false,
            onTapLesson: { lesson in
                selectedLessonDetail = lesson
            },
            onReorder: nil,
            onGiveLesson: { lesson in
                lessonToSchedule = lesson
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
        if isOrganizingGroups {
            organizeGroupsView
        } else {
            expandedGroupsView
        }
    }

    // MARK: - Organize Groups View

    private var organizeGroupsView: some View {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsFromFilteredLessons
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

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
                organizeGroupRow(group: group, in: displayGroups)
            }
            .onMove { source, destination in
                moveGroups(from: source, to: destination, in: displayGroups)
            }
        }
        .listStyle(.plain)
        .id("OrganizeGroupsList")
    }

    private func organizeGroupRow(group: String, in displayGroups: [String]) -> some View {
        let ungroupedLabel = "Ungrouped"
        let groupLessons = lessonsForSubject.filter { lesson in
            let lessonGroupTrimmed = lesson.group.trimmed()
            if group == ungroupedLabel {
                return lessonGroupTrimmed.isEmpty
            } else {
                return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
            }
        }

        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.body)

            Text(group)
                .font(.system(.body, design: .rounded, weight: .medium))

            Spacer()

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

    // MARK: - Expanded Groups View (Grouped by Group)

    private var expandedGroupsView: some View {
        let ungroupedLabel = "Ungrouped"

        // Get ordered groups from reorderableGroups or compute them
        let displayGroups: [String] = {
            let baseGroups = groupsFromFilteredLessons
            let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
            let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

            if reorderableGroups.isEmpty {
                return allGroups
            }
            let existingSet = Set(reorderableGroups)
            let missing = allGroups.filter { !existingSet.contains($0) }
            return reorderableGroups.filter { allGroups.contains($0) } + missing
        }()

        return ScrollViewReader { proxy in
            List {
                expandedGroupsListRows(displayGroups: displayGroups, ungroupedLabel: ungroupedLabel, scrollProxy: proxy)
            }
            .listStyle(.plain)
            .id("PlanModeList")
        }
    }

    @ViewBuilder
    private func expandedGroupsListRows(
        displayGroups: [String],
        ungroupedLabel: String,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        if !canReorderInPlanMode {
            Text("Clear search to reorder lessons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
                .accessibilityLabel("Clear search to reorder lessons")
        }
        ForEach(displayGroups, id: \.self) { group in
            expandedGroupSection(group: group, ungroupedLabel: ungroupedLabel, scrollProxy: scrollProxy)
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func expandedGroupSection(
        group: String, ungroupedLabel: String, scrollProxy: ScrollViewProxy
    ) -> some View {
        let groupLessons = lessonsForGroup(group, ungroupedLabel: ungroupedLabel)

        if !groupLessons.isEmpty {
            let subheadings = orderedSubheadings(for: groupLessons, group: group)

            Section {
                if subheadings.hasSubheadings {
                    ForEach(subheadings.order, id: \.self) { sh in
                        if let shLessons = subheadings.bySubheading[sh], !shLessons.isEmpty {
                            subheadingDisclosureGroup(
                                subheading: sh.isEmpty ? "Other" : sh,
                                lessons: shLessons,
                                group: group,
                                ungroupedLabel: ungroupedLabel,
                                scrollProxy: scrollProxy
                            )
                        }
                    }
                } else {
                    lessonRows(groupLessons, group: group, ungroupedLabel: ungroupedLabel, scrollProxy: scrollProxy)
                }
            } header: {
                if let subject = selectedSubject {
                    groupSectionHeader(group: group, subject: subject)
                } else {
                    Text(group)
                }
            }
        }
    }

    /// Computes ordered subheadings and a lookup for a group's lessons.
    private func orderedSubheadings(for groupLessons: [Lesson], group: String)
        -> (order: [String], bySubheading: [String: [Lesson]], hasSubheadings: Bool) {
        let bySubheading = Dictionary(grouping: groupLessons) { $0.subheading.trimmed() }
        let nonEmpty = Array(Set(bySubheading.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !nonEmpty.isEmpty else {
            return (order: [], bySubheading: bySubheading, hasSubheadings: false)
        }

        let subject = selectedSubject ?? groupLessons.first?.subject ?? ""
        var ordered = FilterOrderStore.loadSubheadingOrder(for: subject, group: group, existing: nonEmpty)
        if bySubheading.keys.contains("") {
            ordered.append("")
        }
        return (order: ordered, bySubheading: bySubheading, hasSubheadings: true)
    }

    /// A collapsible DisclosureGroup for a subheading cluster within a group.
    @ViewBuilder
    private func subheadingDisclosureGroup(
        subheading: String,
        lessons: [Lesson],
        group: String,
        ungroupedLabel: String,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        DisclosureGroup {
            lessonRows(lessons, group: group, ungroupedLabel: ungroupedLabel, scrollProxy: scrollProxy)
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 14)

                Text(subheading)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(lessons.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
    }

    /// Renders lesson rows (with or without reorder handles) for a flat list of lessons.
    @ViewBuilder
    private func lessonRows(
        _ lessons: [Lesson],
        group: String,
        ungroupedLabel: String,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        if canReorderInPlanMode {
            ForEach(lessons, id: \.id) { lesson in
                ExpandedLessonRowView(
                    lesson: lesson,
                    isSelected: selectedLessonDetail?.id == lesson.id,
                    showsReorderHandle: true,
                    onSelect: {
                        guard displayMode != .plan else { return }
                        selectedLessonDetail = lesson
                        scrollToLesson(lesson.id, proxy: scrollProxy)
                    },
                    onSchedule: { lessonToSchedule = lesson }
                )
            }
            .onMove { source, destination in
                moveLessonsInGroup(from: source, to: destination, group: group, ungroupedLabel: ungroupedLabel)
            }
            .moveDisabled(!canReorderInPlanMode)
        } else {
            ForEach(lessons, id: \.id) { lesson in
                ExpandedLessonRowView(
                    lesson: lesson,
                    isSelected: selectedLessonDetail?.id == lesson.id,
                    showsReorderHandle: false,
                    onSelect: {
                        guard displayMode != .plan else { return }
                        selectedLessonDetail = lesson
                        scrollToLesson(lesson.id, proxy: scrollProxy)
                    },
                    onSchedule: { lessonToSchedule = lesson }
                )
            }
        }
    }

    private func scrollToLesson(_ id: UUID, proxy: ScrollViewProxy) {
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
                adaptiveWithAnimation {
                    proxy.scrollTo(id, anchor: .center)
                }
            } catch {
                logger.warning("Task sleep failed in scrollToLesson: \(error)")
            }
        }
    }

    /// Returns sorted lessons for a specific group
    private func lessonsForGroup(_ group: String, ungroupedLabel: String) -> [Lesson] {
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

    /// Move lessons within a group - re-fetches the group lessons to ensure fresh data
    @MainActor
    private func moveLessonsInGroup(from source: IndexSet, to destination: Int, group: String, ungroupedLabel: String) {
        guard canReorderInPlanMode else { return }

        // Get fresh group lessons
        let groupLessons = lessonsForGroup(group, ungroupedLabel: ungroupedLabel)
        moveLessonsInSubject(from: source, to: destination, in: groupLessons)
    }

    // MARK: - Lesson Detail Pane (Right)

    func lessonDetailPane(lesson: Lesson) -> some View {
        LessonDetailView(
            lesson: lesson,
            onSave: { _ in
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

    // MARK: - Group Section Header

    @ViewBuilder
    func groupSectionHeader(group: String, subject: String) -> some View {
        let iconName: String = {
            if GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                do {
                    let settings = try GroupTrackService.getEffectiveTrackSettings(
                        subject: subject,
                        group: group,
                        modelContext: modelContext
                    )
                    return settings.isSequential ? "list.number" : "list.bullet"
                } catch {
                    logger.warning("Failed to get track settings: \(error)")
                    return "list.number"
                }
            }
            return "list.bullet.clipboard"
        }()

        HStack {
            Text(group)
            Spacer()
            Button {
                trackSettingsItem = TrackSettingsItem(subject: subject, group: group)
            } label: {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Configure track settings")
        }
    }
}

// MARK: - Expanded Lesson Row View

/// A row view for lessons in the expanded groups list with selection highlighting
struct ExpandedLessonRowView: View {
    let lesson: Lesson
    let isSelected: Bool
    let showsReorderHandle: Bool
    let onSelect: () -> Void
    let onSchedule: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .help("Drag to reorder")
            }

            VStack(alignment: .leading, spacing: 2) {
                LessonRow(lesson: lesson, secondaryTextStyle: .subheading, showTagIcon: false)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .onTapGesture {
            onSelect()
        }
        #endif
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            Button {
                onSchedule()
            } label: {
                Label("Plan Presentation", systemImage: "tray.and.arrow.down")
            }
        }
        .id(lesson.id)
    }
}
