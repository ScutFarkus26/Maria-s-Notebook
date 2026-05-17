// Maria's Notebook/Lessons/LessonsScopeMapView.swift
//
// Scope-and-sequence "Map" view: every sequence is one labeled row, every lesson
// is a small pill on that row, organized into a spine (Area or Great Lesson).
// Tapping a thread row drills into LessonsScopeThreadFocusView.

import SwiftUI
import CoreData

struct LessonsScopeMapView: View {
    let lessons: [CDLesson]
    /// Optional area filter (nil = show all areas).
    /// Ignored when `spine == .greatLesson` — the Great Lesson spine is intentionally cross-area.
    let selectedArea: String?
    @Binding var spine: MapSpine
    let onSelectThread: (ThreadKey) -> Void

    private let helper = LessonsViewModel()

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
            HStack(spacing: 6) {
                if let icon = section.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(section.color)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows) { row in
                    ThreadRow(
                        threadKey: row.key,
                        lessons: row.lessons,
                        color: AppColors.color(forArea: row.key.area),
                        onTap: { onSelectThread(row.key) }
                    )
                }
            }
        }
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
        // Spine ignores area filter — Great Lesson is intentionally cross-area.
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

        // Lessons with no area — extremely unusual, but render as a final unassigned thread.
        if let arealess = byArea[""], !arealess.isEmpty {
            let sorted = arealess.sorted(by: ThreadRowData.lessonSortOrder)
            rows.append(ThreadRowData(
                key: ThreadKey(area: "", sequence: ""),
                lessons: sorted
            ))
        }
        return rows
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
