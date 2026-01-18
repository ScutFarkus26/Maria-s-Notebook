// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import SwiftData

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
        Group {
            let hasSearchText = !filterState.debouncedSearchText.trimmed().isEmpty
            let shouldShowLessons = (selectedSubject != nil && !selectedSubject!.trimmed().isEmpty) || hasSearchText

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
        .navigationTitle(selectedSubject ?? "Lessons")
        .searchable(text: $filterState.searchText, placement: .toolbar)
    }

    private var browseModeLessons: some View {
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
    var planModeList: some View {
        if isOrganizingGroups {
            organizeGroupsView
        } else {
            expandedGroupsView
        }
    }

    // MARK: - Organize Groups View

    var organizeGroupsView: some View {
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

    // MARK: - Expanded Groups View

    var expandedGroupsView: some View {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsFromFilteredLessons
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let displayGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

        return List {
            ForEach(displayGroups, id: \.self) { group in
                expandedGroupSection(group: group)
            }
        }
        .listStyle(.plain)
        .id("PlanModeList")
    }

    @ViewBuilder
    private func expandedGroupSection(group: String) -> some View {
        let ungroupedLabel = "Ungrouped"
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
                    expandedGroupLessonRow(lesson: lesson)
                }
                .onMove(perform: canReorderInPlanMode ? { source, destination in
                    moveLessonsInSubject(from: source, to: destination, in: groupLessons)
                } : nil)
            }
        }
    }

    private func expandedGroupLessonRow(lesson: Lesson) -> some View {
        HStack(spacing: 12) {
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

    // MARK: - Lesson Detail Pane (Right)

    func lessonDetailPane(lesson: Lesson) -> some View {
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

    // MARK: - Group Section Header

    @ViewBuilder
    func groupSectionHeader(group: String, subject: String) -> some View {
        let iconName: String = {
            if GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                if let settings = try? GroupTrackService.getEffectiveTrackSettings(
                    subject: subject,
                    group: group,
                    modelContext: modelContext
                ) {
                    return settings.isSequential ? "list.number" : "list.bullet"
                }
                return "list.number"
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
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Configure track settings")
        }
    }
}
