// LessonsOutlineView.swift
// Hierarchical outline view for edit mode with direct drag/drop reordering

import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Subheading Drag Payload

/// Drag payload for reordering subheadings within a group. Carrying subject + group
/// lets the drop site reject cross-group drops without callback churn.
struct SubheadingTransfer: Codable, Transferable {
    let subject: String
    let group: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - LessonsOutlineView

/// A hierarchical outline view showing Group > Subheading > CDLesson with
/// DisclosureGroups, context menus, and direct drag-to-reorder.
struct LessonsOutlineView: View {
    let subject: String
    let displayGroups: [String]
    let lessonsByGroup: [String: [CDLesson]]
    let allSubheadings: [String: [String]]
    let selectedLessonID: UUID?
    var isEditing: Bool = false

    var onSelectLesson: ((CDLesson) -> Void)?
    var onScheduleLesson: ((CDLesson) -> Void)?
    var onMoveToGroup: ((CDLesson, String) -> Void)?
    var onMoveToSubheading: ((CDLesson, String) -> Void)?
    var onReorderSubheadings: ((String) -> Void)?
    var onReorderSubheadingByDrag: ((_ group: String, _ source: String, _ target: String) -> Void)?
    var onConfigureTrack: ((String) -> Void)?
    var onMoveLessonsInGroup: ((_ source: IndexSet, _ destination: Int, _ group: String) -> Void)?
    var onMoveGroups: ((_ source: IndexSet, _ destination: Int) -> Void)?
    var onMoveLessonIDToGroup: ((_ lessonID: UUID, _ targetGroup: String) -> Void)?
    var onLocateInMap: ((CDLesson) -> Void)?

    @State private var expandedGroups: Set<String> = []
    @State private var dropTargetSubheading: String?

    var body: some View {
        List {
            if isEditing {
                ForEach(displayGroups, id: \.self) { group in
                    groupDisclosure(group: group)
                }
                .onMove { source, destination in
                    onMoveGroups?(source, destination)
                }
            } else {
                ForEach(displayGroups, id: \.self) { group in
                    groupDisclosure(group: group)
                }
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
            if isEditing {
                ForEach(lessons) { lesson in
                    lessonOutlineRow(lesson: lesson, group: group, subheadings: [])
                }
                .onMove { source, destination in
                    onMoveLessonsInGroup?(source, destination, group)
                }
            } else {
                ForEach(lessons) { lesson in
                    lessonOutlineRow(lesson: lesson, group: group, subheadings: [])
                }
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

            if isEditing {
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
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(dropTargetSubheading == name && !name.isEmpty
                      ? Color.accentColor.opacity(UIConstants.OpacityConstants.moderate)
                      : Color.clear)
                .padding(.horizontal, 4)
        )
        .listRowSeparator(.hidden)
        .when(!name.isEmpty && isEditing) { view in
            view
                .draggable(SubheadingTransfer(subject: subject, group: group, name: name))
                .dropDestination(for: SubheadingTransfer.self) { items, _ in
                    guard let item = items.first,
                          item.subject == subject,
                          item.group == group,
                          item.name != name
                    else { return false }
                    onReorderSubheadingByDrag?(group, item.name, name)
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        dropTargetSubheading = name
                    } else if dropTargetSubheading == name {
                        dropTargetSubheading = nil
                    }
                }
        }

        if isEditing {
            ForEach(lessons) { lesson in
                lessonOutlineRow(lesson: lesson, group: group, subheadings: allGroupSubheadings)
            }
            .onMove { source, destination in
                onMoveLessonsInGroup?(source, destination, group)
            }
        } else {
            ForEach(lessons) { lesson in
                lessonOutlineRow(lesson: lesson, group: group, subheadings: allGroupSubheadings)
            }
        }
    }

    // MARK: - CDLesson Row

    @ViewBuilder
    private func lessonOutlineRow(
        lesson: CDLesson,
        group: String,
        subheadings: [String]
    ) -> some View {
        LessonCompactRow(
            lesson: lesson,
            isSelected: selectedLessonID == lesson.id
        )
        // simultaneousGesture lets tap-to-select coexist with .onMove drag.
        .simultaneousGesture(TapGesture().onEnded { onSelectLesson?(lesson) })
        .contextMenu { lessonContextMenu(lesson: lesson, group: group, subheadings: subheadings) }
        .id(lesson.id)
    }

    // MARK: - Helpers

    fileprivate struct GroupSubheadings {
        let order: [String]
        let bySubheading: [String: [CDLesson]]
        let hasSubheadings: Bool
    }
}

// MARK: - Lesson Context Menu & Subheading Helpers

extension LessonsOutlineView {
    @ViewBuilder
    func lessonContextMenu(
        lesson: CDLesson, group: String, subheadings: [String]
    ) -> some View {
        Button { onSelectLesson?(lesson) } label: {
            Label("View Details", systemImage: "info.circle")
        }
        Button { onScheduleLesson?(lesson) } label: {
            Label("Plan Presentation", systemImage: "tray.and.arrow.down")
        }
        if let onLocateInMap {
            Button { onLocateInMap(lesson) } label: {
                Label("Locate in Map", systemImage: "chart.bar.doc.horizontal")
            }
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

    fileprivate func groupSubheadings(for group: String, lessons: [CDLesson]) -> GroupSubheadings {
        let bySubheading = Dictionary(grouping: lessons) { $0.subheading.trimmed() }

        // Prefer the order computed by the parent (which already consults FilterOrderStore).
        // Fall back to alphabetical for safety.
        let providedOrder: [String] = allSubheadings[group] ?? []
        let presentNonEmpty = Set(bySubheading.keys.filter { !$0.isEmpty })
        var nonEmpty: [String] = providedOrder.filter { presentNonEmpty.contains($0) }
        let missing = presentNonEmpty.subtracting(nonEmpty)
        if !missing.isEmpty {
            let alphabetical = missing.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            nonEmpty.append(contentsOf: alphabetical)
        }

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
