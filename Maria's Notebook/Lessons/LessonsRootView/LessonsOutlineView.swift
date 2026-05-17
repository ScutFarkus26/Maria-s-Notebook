// LessonsOutlineView.swift
// Hierarchical outline view for edit mode with direct drag/drop reordering

import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Section Drag Payload

/// Drag payload for reordering sections within a sequence. Carrying area + sequence
/// lets the drop site reject cross-sequence drops without callback churn.
struct SectionTransfer: Codable, Transferable {
    let area: String
    let sequence: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - LessonsOutlineView

/// A hierarchical outline view showing Group > Section > CDLesson with
/// DisclosureGroups, context menus, and direct drag-to-reorder.
struct LessonsOutlineView: View {
    let area: String
    let displaySequences: [String]
    let lessonsBySequence: [String: [CDLesson]]
    let allSections: [String: [String]]
    let selectedLessonID: UUID?
    var isEditing: Bool = false

    var onSelectLesson: ((CDLesson) -> Void)?
    var onScheduleLesson: ((CDLesson) -> Void)?
    var onMoveToSequence: ((CDLesson, String) -> Void)?
    var onMoveToSection: ((CDLesson, String) -> Void)?
    var onReorderSections: ((String) -> Void)?
    var onReorderSectionByDrag: ((_ sequence: String, _ source: String, _ target: String) -> Void)?
    var onConfigureTrack: ((String) -> Void)?
    var onMoveLessonsInSequence: ((_ source: IndexSet, _ destination: Int, _ sequence: String) -> Void)?
    var onMoveSequences: ((_ source: IndexSet, _ destination: Int) -> Void)?
    var onMoveLessonIDToSequence: ((_ lessonID: UUID, _ targetSequence: String) -> Void)?
    var onLocateInMap: ((CDLesson) -> Void)?

    @State private var expandedSequences: Set<String> = []
    @State private var dropTargetSection: String?

    var body: some View {
        List {
            if isEditing {
                ForEach(displaySequences, id: \.self) { sequence in
                    groupDisclosure(sequence: sequence)
                }
                .onMove { source, destination in
                    onMoveSequences?(source, destination)
                }
            } else {
                ForEach(displaySequences, id: \.self) { sequence in
                    groupDisclosure(sequence: sequence)
                }
            }
        }
        .listStyle(.plain)
        .task { expandedSequences = Set(displaySequences) }
    }

    // MARK: - Group Level

    @ViewBuilder
    private func groupDisclosure(sequence: String) -> some View {
        let lessons = lessonsBySequence[sequence] ?? []
        let sections = sequenceSections(for: sequence, lessons: lessons)

        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSequences.contains(sequence) },
                set: { isExpanded in
                    if isExpanded {
                        expandedSequences.insert(sequence)
                    } else {
                        expandedSequences.remove(sequence)
                    }
                }
            )
        ) {
            groupContent(sequence: sequence, lessons: lessons, sections: sections)
        } label: {
            groupLabel(sequence: sequence, lessons: lessons, sections: sections)
        }
    }

    // MARK: - Group Content

    @ViewBuilder
    private func groupContent(
        sequence: String,
        lessons: [CDLesson],
        sections: SequenceSections
    ) -> some View {
        if sections.hasSections {
            ForEach(sections.order, id: \.self) { sh in
                if let shLessons = sections.bySection[sh], !shLessons.isEmpty {
                    sectionSection(
                        name: sh,
                        lessons: shLessons,
                        sequence: sequence,
                        allSequenceSections: sections.order
                    )
                }
            }
        } else {
            if isEditing {
                ForEach(lessons) { lesson in
                    lessonOutlineRow(lesson: lesson, sequence: sequence, sections: [])
                }
                .onMove { source, destination in
                    onMoveLessonsInSequence?(source, destination, sequence)
                }
            } else {
                ForEach(lessons) { lesson in
                    lessonOutlineRow(lesson: lesson, sequence: sequence, sections: [])
                }
            }
        }
    }

    // MARK: - Group Label

    @ViewBuilder
    private func groupLabel(
        sequence: String,
        lessons: [CDLesson],
        sections: SequenceSections
    ) -> some View {
        HStack {
            Text(sequence)
                .font(.system(.body, design: .rounded, weight: .semibold))
            Spacer()

            if isEditing {
                if sections.hasSections {
                    Button {
                        onReorderSections?(sequence)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reorder sections")
                }

                Button {
                    onConfigureTrack?(sequence)
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

    // MARK: - Section Level

    @ViewBuilder
    private func sectionSection(
        name: String,
        lessons: [CDLesson],
        sequence: String,
        allSequenceSections: [String]
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
                .fill(dropTargetSection == name && !name.isEmpty
                      ? Color.accentColor.opacity(UIConstants.OpacityConstants.moderate)
                      : Color.clear)
                .padding(.horizontal, 4)
        )
        .listRowSeparator(.hidden)
        .when(!name.isEmpty && isEditing) { view in
            view
                .draggable(SectionTransfer(area: area, sequence: sequence, name: name))
                .dropDestination(for: SectionTransfer.self) { items, _ in
                    guard let item = items.first,
                          item.area == area,
                          item.sequence == sequence,
                          item.name != name
                    else { return false }
                    onReorderSectionByDrag?(sequence, item.name, name)
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        dropTargetSection = name
                    } else if dropTargetSection == name {
                        dropTargetSection = nil
                    }
                }
        }

        if isEditing {
            ForEach(lessons) { lesson in
                lessonOutlineRow(lesson: lesson, sequence: sequence, sections: allSequenceSections)
            }
            .onMove { source, destination in
                onMoveLessonsInSequence?(source, destination, sequence)
            }
        } else {
            ForEach(lessons) { lesson in
                lessonOutlineRow(lesson: lesson, sequence: sequence, sections: allSequenceSections)
            }
        }
    }

    // MARK: - CDLesson Row

    @ViewBuilder
    private func lessonOutlineRow(
        lesson: CDLesson,
        sequence: String,
        sections: [String]
    ) -> some View {
        LessonCompactRow(
            lesson: lesson,
            isSelected: selectedLessonID == lesson.id
        )
        // simultaneousGesture lets tap-to-select coexist with .onMove drag.
        .simultaneousGesture(TapGesture().onEnded { onSelectLesson?(lesson) })
        .contextMenu { lessonContextMenu(lesson: lesson, sequence: sequence, sections: sections) }
        .id(lesson.id)
    }

    // MARK: - Helpers

    fileprivate struct SequenceSections {
        let order: [String]
        let bySection: [String: [CDLesson]]
        let hasSections: Bool
    }
}

// MARK: - Lesson Context Menu & Section Helpers

extension LessonsOutlineView {
    @ViewBuilder
    func lessonContextMenu(
        lesson: CDLesson, sequence: String, sections: [String]
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

        let otherSequences = displaySequences.filter { $0 != sequence }
        if !otherSequences.isEmpty {
            Menu("Move to Group\u{2026}") {
                ForEach(otherSequences, id: \.self) { targetSequence in
                    Button(targetSequence) { onMoveToSequence?(lesson, targetSequence) }
                }
            }
        }

        let otherSections = sections.filter { $0 != lesson.section.trimmed() }
        if !otherSections.isEmpty {
            Menu("Move to Section\u{2026}") {
                ForEach(otherSections, id: \.self) { targetSh in
                    Button(targetSh.isEmpty ? "Other" : targetSh) {
                        onMoveToSection?(lesson, targetSh)
                    }
                }
            }
        }
    }

    fileprivate func sequenceSections(for sequence: String, lessons: [CDLesson]) -> SequenceSections {
        let bySection = Dictionary(grouping: lessons) { $0.section.trimmed() }

        // Prefer the order computed by the parent (which already consults FilterOrderStore).
        // Fall back to alphabetical for safety.
        let providedOrder: [String] = allSections[sequence] ?? []
        let presentNonEmpty = Set(bySection.keys.filter { !$0.isEmpty })
        var nonEmpty: [String] = providedOrder.filter { presentNonEmpty.contains($0) }
        let missing = presentNonEmpty.subtracting(nonEmpty)
        if !missing.isEmpty {
            let alphabetical = missing.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            nonEmpty.append(contentsOf: alphabetical)
        }

        guard !nonEmpty.isEmpty else {
            return SequenceSections(order: [], bySection: bySection, hasSections: false)
        }

        var ordered = nonEmpty
        if bySection.keys.contains("") {
            ordered.append("")
        }
        return SequenceSections(order: ordered, bySection: bySection, hasSections: true)
    }
}
