// Maria's Notebook/Lessons/LessonSectionGrouping.swift

import Foundation

/// Splits one sequence's lessons into the section bands that both the
/// scope-and-sequence map and the Checklist grid draw.
///
/// A guide reads one of those screens against the other, so the rule lives here
/// rather than being spelled out at each call site — three copies of it had already
/// drifted apart. Sections match case-insensitively, so "Chains" and "chains" are
/// one band rather than two (labelled with whichever spelling comes first in
/// curriculum order); the named bands follow the order stored for the
/// (area, sequence) pair; and the lessons with no section of their own trail them.
enum LessonSectionGrouping {

    /// One band of lessons. An empty `name` is the unsectioned bucket, which callers
    /// label "Other".
    struct Band {
        let name: String
        let lessons: [CDLesson]
    }

    /// The bands for `lessons`, each already in curriculum order. `lessons` may arrive
    /// in any order — it is sorted here — but has to be narrowed to the one
    /// (area, sequence) thread being drawn.
    @MainActor
    static func bands(for lessons: [CDLesson], area: String, sequence: String) -> [Band] {
        let folded = fold(lessons)
        let existing = alphabetized(folded.labels)

        let trimmedArea = area.trimmed()
        // With no area there is nothing to key a stored order on, so alphabetical stands.
        let order: [String] = trimmedArea.isEmpty || existing.isEmpty
            ? existing
            : FilterOrderStore.loadSectionOrder(
                for: trimmedArea, sequence: sequence.trimmed(), existing: existing
            )

        var bands: [Band] = order.compactMap { name in
            guard let inBand = folded.bucketed[name.normalizedForComparison()], !inBand.isEmpty else {
                return nil
            }
            return Band(name: name, lessons: inBand)
        }
        if !folded.unsectioned.isEmpty {
            bands.append(Band(name: "", lessons: folded.unsectioned))
        }
        return bands
    }

    /// The distinct section names in `lessons`, alphabetised — the list a stored
    /// order is merged against. Used by the reorder sheet so it offers exactly the
    /// bands the map and the Checklist draw.
    @MainActor
    static func sectionNames(in lessons: [CDLesson]) -> [String] {
        alphabetized(fold(lessons).labels)
    }

    // MARK: - Private

    private struct Folded {
        var labels: [String: String] = [:]
        var bucketed: [String: [CDLesson]] = [:]
        var unsectioned: [CDLesson] = []
    }

    /// Buckets by case-folded section name, keeping the spelling seen first in
    /// curriculum order as the band's label.
    @MainActor
    private static func fold(_ lessons: [CDLesson]) -> Folded {
        var folded = Folded()
        for lesson in lessons.sorted(by: ThreadRowData.lessonSortOrder) {
            let name = lesson.section.trimmed()
            guard !name.isEmpty else {
                folded.unsectioned.append(lesson)
                continue
            }
            let key = name.normalizedForComparison()
            if folded.labels[key] == nil { folded.labels[key] = name }
            folded.bucketed[key, default: []].append(lesson)
        }
        return folded
    }

    private static func alphabetized(_ labels: [String: String]) -> [String] {
        labels.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
