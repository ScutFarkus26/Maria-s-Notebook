// Cosmic Daybook/Lessons/Library/LessonSectionGrouping.swift

import Foundation

/// Splits one sequence's lessons into the section bands that the scope-and-sequence
/// map, the Checklist grid and `find_lessons` all draw.
///
/// A guide reads one of those against another, so the rule lives here rather than
/// being spelled out at each call site — three copies of it had already drifted apart.
///
/// The lessons' own order decides everything (2026-11-09). Sections match
/// case-insensitively, so "Chains" and "chains" are one band (labelled with whichever
/// spelling comes first in curriculum order), and each band sits where its earliest
/// lesson falls. Lessons with no section sit where their order puts them too: each run
/// of them between two sections is a band of its own, rather than one bucket trailing
/// the rest. There is no stored section order any more; to move a section, move its
/// lessons. (Before, the named bands were alphabetical unless a guide had dragged them
/// into an order, and the unsectioned lessons always came last.)
enum LessonSectionGrouping {

    /// One band of lessons. An empty `name` is a run of lessons with no section,
    /// which callers label "Other"; a sequence can have several such runs.
    struct Band {
        let name: String
        let lessons: [CDLesson]
    }

    /// The bands for `lessons`, each already in curriculum order. `lessons` may arrive
    /// in any order — it is sorted here — but has to be narrowed to the one
    /// (area, sequence) thread being drawn.
    static func bands(for lessons: [CDLesson]) -> [Band] {
        let sorted = lessons.sorted(by: ThreadRowData.lessonSortOrder)

        // A named band's lessons, by case-folded name, and the spelling seen first.
        var labels: [String: String] = [:]
        var bucketed: [String: [CDLesson]] = [:]
        for lesson in sorted {
            let name = lesson.section.trimmed()
            guard !name.isEmpty else { continue }
            let key = name.normalizedForComparison()
            if labels[key] == nil { labels[key] = name }
            bucketed[key, default: []].append(lesson)
        }

        // Walk the lessons in order. A named band is drawn whole at its first lesson;
        // an unsectioned lesson joins the run of them in progress, and a named band
        // starting ends that run.
        var bands: [Band] = []
        var placed = Set<String>()
        var run: [CDLesson] = []
        for lesson in sorted {
            let name = lesson.section.trimmed()
            guard !name.isEmpty else {
                run.append(lesson)
                continue
            }
            let key = name.normalizedForComparison()
            guard placed.insert(key).inserted else { continue }
            if !run.isEmpty {
                bands.append(Band(name: "", lessons: run))
                run = []
            }
            bands.append(Band(name: labels[key] ?? name, lessons: bucketed[key] ?? []))
        }
        if !run.isEmpty {
            bands.append(Band(name: "", lessons: run))
        }
        return bands
    }
}
