// Maria's Notebook/Lessons/LessonsScopeMapView.swift
//
// Scope-and-sequence "Map" view: every sequence is one labeled row, every lesson
// is a small pill on that row, organized into a spine (Area or Great Lesson).
// Tapping a thread row drills into LessonsScopeThreadFocusView.
// In edit mode, rows are draggable to reorder within their area section.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Sequence drag-drop payload

struct SequenceTransfer: Codable, Transferable {
    let area: String
    let sequence: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - LessonsScopeMapView

struct LessonsScopeMapView: View {
    let lessons: [CDLesson]
    /// Optional area filter (nil = show all areas).
    /// Ignored when `spine == .greatLesson` — the Great Lesson spine is intentionally cross-area.
    let selectedArea: String?
    @Binding var spine: MapSpine
    var isEditing: Bool = false
    let onSelectThread: (ThreadKey) -> Void
    var onMoveSequences: ((IndexSet, Int, String) -> Void)?
    var onConfigureTrack: ((ThreadKey) -> Void)?
    var onReorderSections: ((ThreadKey) -> Void)?
    var onFocusArea: ((String) -> Void)?
    var onClearAreaFocus: (() -> Void)?

    private let helper = LessonsViewModel()

    @State private var dropTargetSequence: String?

    private var hasAreaFocus: Bool {
        guard let selectedArea else { return false }
        return !selectedArea.trimmed().isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                spinePicker

                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MapSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(section)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows) { row in
                    let hasSect = hasMultipleSections(row: row)
                    ThreadRow(
                        threadKey: row.key,
                        lessons: row.lessons,
                        color: AppColors.color(forArea: row.key.area),
                        isEditing: isEditing,
                        hasSections: hasSect,
                        onTap: { onSelectThread(row.key) },
                        onConfigureTrack: { onConfigureTrack?(row.key) },
                        onReorderSections: { onReorderSections?(row.key) }
                    )
                    .when(isEditing && !row.key.area.isEmpty) { view in
                        view
                            .draggable(SequenceTransfer(area: row.key.area, sequence: row.key.sequence))
                            .dropDestination(for: SequenceTransfer.self) { items, _ in
                                guard let item = items.first,
                                      item.area == row.key.area,
                                      item.sequence != row.key.sequence
                                else { return false }
                                let rowSequences = section.rows.map { $0.key.sequence }
                                guard let srcIdx = rowSequences.firstIndex(of: item.sequence),
                                      let dstIdx = rowSequences.firstIndex(of: row.key.sequence)
                                else { return false }
                                let adjustedDst = dstIdx > srcIdx ? dstIdx + 1 : dstIdx
                                onMoveSequences?(IndexSet(integer: srcIdx), adjustedDst, row.key.area)
                                return true
                            } isTargeted: { isTargeted in
                                if isTargeted {
                                    dropTargetSequence = row.key.sequence
                                } else if dropTargetSequence == row.key.sequence {
                                    dropTargetSequence = nil
                                }
                            }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor.opacity(dropTargetSequence == row.key.sequence ? 0.6 : 0), lineWidth: 1.5)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: MapSection) -> some View {
        // Area-spine headers double as area filters; Great Lesson headers stay static.
        let isAreaSpine = (spine == .area)
        let canTap = isAreaSpine && (hasAreaFocus ? onClearAreaFocus != nil : onFocusArea != nil)

        Button {
            if !isAreaSpine { return }
            if hasAreaFocus {
                onClearAreaFocus?()
            } else {
                onFocusArea?(section.title)
            }
        } label: {
            HStack(spacing: 6) {
                if isAreaSpine && hasAreaFocus {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                } else if let icon = section.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isAreaSpine && hasAreaFocus
                     ? "All Areas".uppercased()
                     : section.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                if isAreaSpine && hasAreaFocus {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(section.color)
                }
            }
            .foregroundStyle(isAreaSpine && hasAreaFocus ? Color.secondary : section.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
        .help({
            if !isAreaSpine { return "" }
            return hasAreaFocus ? "Show all areas" : "Focus on \(section.title)"
        }())
    }

    private var spinePicker: some View {
        HStack(spacing: 8) {
            Text("Spine")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Picker("Spine", selection: $spine) {
                ForEach(MapSpine.allCases) { option in
                    Label(option.rawValue, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var sections: [MapSection] {
        switch spine {
        case .area:
            return areaSections()
        case .greatLesson:
            return greatLessonSections()
        }
    }

    private func areaSections() -> [MapSection] {
        let areas: [String]
        if let selectedArea, !selectedArea.trimmed().isEmpty {
            areas = [selectedArea]
        } else {
            areas = helper.areas(from: lessons)
        }

        return areas.compactMap { area -> MapSection? in
            let rows = threadRowsForArea(area, lessons: lessonsInArea(area))
            guard !rows.isEmpty else { return nil }
            return MapSection(
                id: "area:\(area)",
                title: area,
                color: AppColors.color(forArea: area),
                icon: nil,
                rows: rows
            )
        }
    }

    private func greatLessonSections() -> [MapSection] {
        var unassigned: [CDLesson] = []
        var byGreatLesson: [GreatLesson: [CDLesson]] = [:]

        for lesson in lessons {
            let resolved = GreatLesson.resolve(for: lesson)
            if let primary = resolved.first {
                byGreatLesson[primary, default: []].append(lesson)
            } else {
                unassigned.append(lesson)
            }
        }

        var result: [MapSection] = []
        for greatLesson in GreatLesson.allCases {
            guard let bucket = byGreatLesson[greatLesson], !bucket.isEmpty else { continue }
            let rows = threadRowsAcrossAreas(lessons: bucket)
            guard !rows.isEmpty else { continue }
            result.append(MapSection(
                id: "greatLesson:\(greatLesson.rawValue)",
                title: greatLesson.shortName,
                color: greatLesson.color,
                icon: greatLesson.icon,
                rows: rows
            ))
        }

        if !unassigned.isEmpty {
            let rows = threadRowsAcrossAreas(lessons: unassigned)
            if !rows.isEmpty {
                result.append(MapSection(
                    id: "greatLesson:unassigned",
                    title: "Unassigned",
                    color: .secondary,
                    icon: "questionmark.circle",
                    rows: rows
                ))
            }
        }

        return result
    }

    // MARK: - Thread row builders

    private func lessonsInArea(_ area: String) -> [CDLesson] {
        let key = area.trimmed().lowercased()
        return lessons.filter { $0.area.trimmed().lowercased() == key }
    }

    /// Thread rows for a single area — order respects FilterOrderStore via `helper.groups`.
    private func threadRowsForArea(_ area: String, lessons areaLessons: [CDLesson]) -> [ThreadRowData] {
        let groups = helper.groups(for: area, lessons: lessons)
        var rows: [ThreadRowData] = []

        for sequence in groups {
            let sequenceKey = sequence.trimmed().lowercased()
            let inSequence = areaLessons
                .filter { $0.sequence.trimmed().lowercased() == sequenceKey }
                .sorted(by: ThreadRowData.lessonSortOrder)
            if !inSequence.isEmpty {
                rows.append(ThreadRowData(
                    key: ThreadKey(area: area, sequence: sequence),
                    lessons: inSequence
                ))
            }
        }

        let ungrouped = areaLessons
            .filter { $0.sequence.trimmed().isEmpty }
            .sorted(by: ThreadRowData.lessonSortOrder)
        if !ungrouped.isEmpty {
            rows.append(ThreadRowData(
                key: ThreadKey(area: area, sequence: ""),
                lessons: ungrouped
            ))
        }

        return rows
    }

    /// Thread rows aggregated from a heterogeneous lesson set. Used by Great Lesson spine
    /// where one section spans multiple areas. Areas are interleaved alphabetically
    /// within the section so threads stay grouped by their parent area.
    private func threadRowsAcrossAreas(lessons bucket: [CDLesson]) -> [ThreadRowData] {
        let byArea = Dictionary(grouping: bucket) { $0.area.trimmed() }
        let orderedAreas = byArea.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var rows: [ThreadRowData] = []
        for area in orderedAreas {
            guard !area.isEmpty, let areaLessons = byArea[area] else { continue }
            rows.append(contentsOf: threadRowsForArea(area, lessons: areaLessons))
        }

        if let arealess = byArea[""], !arealess.isEmpty {
            let sorted = arealess.sorted(by: ThreadRowData.lessonSortOrder)
            rows.append(ThreadRowData(
                key: ThreadKey(area: "", sequence: ""),
                lessons: sorted
            ))
        }
        return rows
    }

    // MARK: - Helpers

    private func hasMultipleSections(row: ThreadRowData) -> Bool {
        let sections = Set(row.lessons.map { $0.section.trimmed() }.filter { !$0.isEmpty })
        return sections.count > 1
    }
}

// MARK: - Section model

struct MapSection: Identifiable {
    let id: String
    let title: String
    let color: Color
    let icon: String?
    let rows: [ThreadRowData]
}

struct ThreadRowData: Identifiable {
    let key: ThreadKey
    let lessons: [CDLesson]

    var id: String { key.id }

    static func lessonSortOrder(_ lhs: CDLesson, _ rhs: CDLesson) -> Bool {
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
