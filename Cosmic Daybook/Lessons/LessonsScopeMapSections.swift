// Cosmic Daybook/Lessons/LessonsScopeMapSections.swift
//
// The rows and sections behind LessonsScopeMapView: one row per sequence, grouped
// into a spine of either areas or Great Lessons. Kept out of the view so the map
// only has to draw and drag what this hands it.

import SwiftUI
import CoreData

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

// MARK: - Builder

struct MapSectionBuilder {
    let lessons: [CDLesson]
    /// Optional area filter (nil = show all areas).
    /// Ignored for the Great Lesson spine — that spine is intentionally cross-area.
    let selectedArea: String?

    private let helper = LessonsViewModel()

    func sections(for spine: MapSpine) -> [MapSection] {
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
}

// MARK: - Reorder geometry

extension MapSection {
    /// Rows here that belong to `area` and carry a real sequence name. The "Other" row
    /// (no sequence) is excluded: it has no stored position and always trails its
    /// area's named sequences.
    func movableSequences(in area: String) -> [String] {
        rows
            .filter { $0.key.area == area && !$0.key.sequence.trimmed().isEmpty }
            .map { $0.key.sequence }
    }

    /// A row can only be dragged when it has somewhere to go: a named sequence in a
    /// real area, sharing this section with at least one sibling.
    func canMove(_ row: ThreadRowData) -> Bool {
        guard !row.key.area.trimmed().isEmpty, !row.key.sequence.trimmed().isEmpty else { return false }
        return movableSequences(in: row.key.area).count > 1
    }

    /// Rows are keyed by section as well as thread: in the Great Lesson spine one
    /// sequence can surface in more than one section, and each copy has its own frame.
    func rowID(for row: ThreadRowData) -> String {
        "\(id)||\(row.id)"
    }
}
