// LessonsOutlineView.swift
// Hierarchical outline view for plan mode with jiggle-mode drag/drop reordering

import SwiftUI
import CoreData

// MARK: - LessonsOutlineView

/// A hierarchical outline view showing Group > Subheading > CDLesson with
/// DisclosureGroups, context menus, and iOS-style jiggle mode for reordering.
struct LessonsOutlineView: View {
    let subject: String
    let displayGroups: [String]
    let lessonsByGroup: [String: [CDLesson]]
    let allSubheadings: [String: [String]]
    let selectedLessonID: UUID?
    let isJiggling: Bool

    var onSelectLesson: ((CDLesson) -> Void)?
    var onScheduleLesson: ((CDLesson) -> Void)?
    var onMoveToGroup: ((CDLesson, String) -> Void)?
    var onMoveToSubheading: ((CDLesson, String) -> Void)?
    var onReorderSubheadings: ((String) -> Void)?
    var onConfigureTrack: ((String) -> Void)?
    var onActivateJiggle: (() -> Void)?
    var onMoveLessonsInGroup: ((_ source: IndexSet, _ destination: Int, _ group: String) -> Void)?
    var onMoveGroups: ((_ source: IndexSet, _ destination: Int) -> Void)?
    var onMoveLessonIDToGroup: ((_ lessonID: UUID, _ targetGroup: String) -> Void)?

    @State private var expandedGroups: Set<String> = []
    var body: some View {
        List {
            ForEach(displayGroups, id: \.self) { group in
                groupDisclosure(group: group)
            }
            .onMove { source, destination in
                onMoveGroups?(source, destination)
            }
        }
        .listStyle(.plain)
        .task { expandedGroups = Set(displayGroups) }
    }

    // MARK: - Group Level

    @ViewBuilder
    private func groupDisclosure(group: String) -> some View {
        let lessons = lessonsByGroup[group] ?? []
        let subheadings = groupSubheadings(for: group, lessons: lessons)

        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedGroups.contains(group) },
                set: { isExpanded in
                    if isExpanded {
                        expandedGroups.insert(group)
                    } else {
                        expandedGroups.remove(group)
                    }
                }
            )
        ) {
            groupContent(group: group, lessons: lessons, subheadings: subheadings)
        } label: {
            groupLabel(group: group, lessons: lessons, subheadings: subheadings)
        }
    }

    // MARK: - Group Content

    @ViewBuilder
    private func groupContent(
        group: String,
        lessons: [CDLesson],
        subheadings: GroupSubheadings
    ) -> some View {
        if subheadings.hasSubheadings {
            ForEach(subheadings.order, id: \.self) { sh in
                if let shLessons = subheadings.bySubheading[sh], !shLessons.isEmpty {
                    subheadingSection(
                        name: sh,
                        lessons: shLessons,
                        group: group,
                        allGroupSubheadings: subheadings.order
                    )
                }
            }
        } else {
            ForEach(lessons) { lesson in
                lessonOutlineRow(lesson: lesson, group: group, subheadings: [])
            }
            .onMove { source, destination in
                onMoveLessonsInGroup?(source, destination, group)
            }
        }
    }

    // MARK: - Group Label

    @ViewBuilder
    private func groupLabel(
        group: String,
        lessons: [CDLesson],
        subheadings: GroupSubheadings
    ) -> some View {
        HStack {
            Text(group)
                .font(.system(.body, design: .rounded, weight: .semibold))
            Spacer()

            if !isJiggling {
                if subheadings.hasSubheadings {
                    Button {
                        onReorderSubheadings?(group)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reorder subheadings")
                }

                Button {
                    onConfigureTrack?(group)
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Configure track settings")
            }

            Text("\(lessons.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(UIConstants.OpacityConstants.light))
                .clipShape(Capsule())
        }
    }

    // MARK: - Subheading Level

    @ViewBuilder
    private func subheadingSection(
        name: String,
        lessons: [CDLesson],
        group: String,
        allGroupSubheadings: [String]
    ) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(UIConstants.OpacityConstants.semi))
                .frame(width: 3, height: 14)
            Text(name.isEmpty ? "Other" : name)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(lessons.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        ForEach(lessons) { lesson in
            lessonOutlineRow(lesson: lesson, group: group, subheadings: allGroupSubheadings)
        }
        .onMove { source, destination in
            onMoveLessonsInGroup?(source, destination, group)
        }
    }

    // MARK: - CDLesson Row

    @ViewBuilder
    private func lessonOutlineRow(
        lesson: CDLesson,
        group: String,
        subheadings: [String]
    ) -> some View {
        let isSelected = selectedLessonID == lesson.id
        let lessonSeed = (lessonsByGroup[group] ?? [])
            .firstIndex(where: { $0.id == lesson.id }) ?? 0
        let displayName = lesson.name.isEmpty ? "Untitled CDLesson" : lesson.name

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                if !lesson.subheading.trimmed().isEmpty {
                    Text(lesson.subheading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        // When jiggling, don't add tap/long-press as high-priority — they block .onMove drag.
        // Use simultaneousGesture for tap so it doesn't eat the drag, and skip long-press entirely.
        .when(!isJiggling) { view in
            view
                .onTapGesture { onSelectLesson?(lesson) }
                .onLongPressGesture(minimumDuration: 0.4) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    onActivateJiggle?()
                }
        }
        .when(isJiggling) { view in
            view.simultaneousGesture(TapGesture().onEnded { onSelectLesson?(lesson) })
        }
        .jiggle(isActive: isJiggling, seed: lessonSeed)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.moderate) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contextMenu { lessonContextMenu(lesson: lesson, group: group, subheadings: subheadings) }
        .id(lesson.id)
    }

    @ViewBuilder
    private func lessonContextMenu(
        lesson: CDLesson, group: String, subheadings: [String]
    ) -> some View {
        Button { onSelectLesson?(lesson) } label: {
            Label("View Details", systemImage: "info.circle")
        }
        Button { onScheduleLesson?(lesson) } label: {
            Label("Plan Presentation", systemImage: "tray.and.arrow.down")
        }
        Divider()

        let otherGroups = displayGroups.filter { $0 != group }
        if !otherGroups.isEmpty {
            Menu("Move to Group\u{2026}") {
                ForEach(otherGroups, id: \.self) { targetGroup in
                    Button(targetGroup) { onMoveToGroup?(lesson, targetGroup) }
                }
            }
        }

        let otherSubheadings = subheadings.filter { $0 != lesson.subheading.trimmed() }
        if !otherSubheadings.isEmpty {
            Menu("Move to Subheading\u{2026}") {
                ForEach(otherSubheadings, id: \.self) { targetSh in
                    Button(targetSh.isEmpty ? "Other" : targetSh) {
                        onMoveToSubheading?(lesson, targetSh)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private struct GroupSubheadings {
        let order: [String]
        let bySubheading: [String: [CDLesson]]
        let hasSubheadings: Bool
    }

    private func groupSubheadings(for group: String, lessons: [CDLesson]) -> GroupSubheadings {
        let bySubheading = Dictionary(grouping: lessons) { $0.subheading.trimmed() }
        let nonEmpty = Array(Set(bySubheading.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !nonEmpty.isEmpty else {
            return GroupSubheadings(order: [], bySubheading: bySubheading, hasSubheadings: false)
        }

        var ordered = nonEmpty
        if bySubheading.keys.contains("") {
            ordered.append("")
        }
        return GroupSubheadings(order: ordered, bySubheading: bySubheading, hasSubheadings: true)
    }
}
