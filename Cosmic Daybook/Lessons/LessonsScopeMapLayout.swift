// Cosmic Daybook/Lessons/LessonsScopeMapLayout.swift
//
// What LessonsScopeMapView draws, built once per change of its inputs: the
// builder's sections with each row's derived facts (MapLayout), and the memo
// that keeps a build until an input moves (MapLayoutMemo).

import SwiftUI
import CoreData

/// The builder's sections with what the map reads for each row worked out once:
/// the key its frame and hover go by, whether it can be dragged, whether its
/// lessons carry more than one named section, and its colour. The map used to
/// derive all four for every row on every body pass.
struct MapLayout {
    struct Row: Identifiable {
        let data: ThreadRowData
        /// `MapSection.rowID(for:)`.
        let rowID: String
        /// `MapSection.canMove(_:)`.
        let isMovable: Bool
        /// More than one named section among the row's lessons.
        let hasSections: Bool
        let color: Color

        /// The thread's key, the identity the map's rows have always had.
        var id: String { data.id }
    }

    struct Section: Identifiable {
        let section: MapSection
        let rows: [Row]

        var id: String { section.id }

        /// The row a lifted `row` would land on with the pointer at `y`, restricted
        /// to rows it can actually swap with: same area, draggable, and close enough
        /// vertically to be a deliberate target. `frames` are rows' frames by row ID,
        /// in the space `y` is measured in.
        func nearestRowID(to y: CGFloat, from row: Row, frames: [String: CGRect], canReorder: Bool) -> String? {
            var best: (id: String, frame: CGRect)?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for candidate in rows where candidate.data.key.area == row.data.key.area {
                guard candidate.rowID != row.rowID,
                      canReorder && candidate.isMovable,
                      let frame = frames[candidate.rowID]
                else { continue }
                let distance = abs(frame.midY - y)
                guard distance < bestDistance else { continue }
                bestDistance = distance
                best = (candidate.rowID, frame)
            }
            // Too far from any row to be a deliberate target.
            guard let best, bestDistance <= best.frame.height else { return nil }
            return best.id
        }
    }

    let sections: [Section]

    init(sections: [MapSection]) {
        self.sections = sections.map { section in
            // `canMove` asks whether the row's area has another named sequence in
            // this section; count those once instead of once per row.
            var namedRowsPerArea: [String: Int] = [:]
            for row in section.rows where !row.key.sequence.trimmed().isEmpty {
                namedRowsPerArea[row.key.area, default: 0] += 1
            }
            let rows = section.rows.map { row in
                Row(
                    data: row,
                    rowID: section.rowID(for: row),
                    isMovable: !row.key.area.trimmed().isEmpty
                        && !row.key.sequence.trimmed().isEmpty
                        && namedRowsPerArea[row.key.area, default: 0] > 1,
                    hasSections: Self.hasMultipleSections(row.lessons),
                    color: AppColors.color(forArea: row.key.area)
                )
            }
            return Section(section: section, rows: rows)
        }
    }

    /// Whether two of `lessons` carry different named sections: the map's old
    /// `Set(sections).count > 1`, stopping at the second name.
    private static func hasMultipleSections(_ lessons: [CDLesson]) -> Bool {
        var firstName: String?
        for lesson in lessons {
            let name = lesson.section.trimmed()
            if name.isEmpty { continue }
            if let firstName, firstName != name { return true }
            if firstName == nil { firstName = name }
        }
        return false
    }
}

/// Keeps the map's layout until one of its inputs moves.
///
/// The map is redrawn on every Lessons screen pass — each frame of a detail
/// divider drag, each hover and hold on the map — and each redraw used to group
/// and sort the whole catalog again. A build reads the lessons passed in (which,
/// and in what order), their area, sequence, order, name, section and Great
/// Lesson, the area filter, the spine, and the saved area and sequence orders;
/// this builds again only when one of those moved.
final class MapLayoutMemo {
    /// What a build reads besides the lessons' own attributes.
    private struct Inputs: Equatable {
        let lessons: [CDLesson]
        let selectedArea: String?
        let spine: MapSpine
        let orderRevision: Int
    }

    private var lessonChanges: ManagedObjectChangeFlag?
    private var inputs: Inputs?
    private var cached: MapLayout?
    /// Builds so far.
    private(set) var buildCount = 0

    func layout(
        for lessons: [CDLesson],
        selectedArea: String?,
        spine: MapSpine,
        in context: NSManagedObjectContext
    ) -> MapLayout {
        let flag: ManagedObjectChangeFlag
        if let existing = lessonChanges, existing.watches(context) {
            flag = existing
        } else {
            // Starts dirty, so a new context always builds.
            flag = ManagedObjectChangeFlag(entityNames: ["Lesson"], context: context)
            lessonChanges = flag
        }
        let lessonChanged = flag.consume(pendingIn: context)
        let current = Inputs(
            lessons: lessons,
            selectedArea: selectedArea,
            spine: spine,
            orderRevision: FilterOrderStore.revision
        )
        if !lessonChanged, current == inputs, let cached { return cached }

        buildCount += 1
        let layout = MapLayout(
            sections: MapSectionBuilder(lessons: lessons, selectedArea: selectedArea).sections(for: spine)
        )
        inputs = current
        cached = layout
        return layout
    }
}
