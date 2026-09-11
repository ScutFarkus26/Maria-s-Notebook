//
//  BlockingAlgorithmEngine+SequenceOrder.swift
//  Maria's Notebook
//
//  Which lesson comes before, and which comes after, for the whole library
//  at once.
//
//  `findPrecedingLesson` / `PlanNextLessonService.findNextLesson` answer for
//  one lesson by filtering and sorting the whole array, which is the right
//  shape for a single question and the wrong one for a sweep: called in a
//  loop over the library it is O(L²), with four trimmed-string allocations
//  per comparison. Grouping once by (area, sequence) and sorting each group
//  once gives the same answers — a group is exactly the candidate set the
//  per-lesson filter produced — and the two caches share the grouping.
//

import CoreData
import Foundation

extension BlockingAlgorithmEngine {

    /// Preceding lesson for every lesson in the library, keyed by lesson id.
    ///
    /// Use this instead of calling `findPrecedingLesson` in a loop over the
    /// library — on a full album curriculum that was millions of comparisons
    /// on the main actor per Presentations refresh.
    nonisolated static func buildPrecedingLessonCache(_ lessons: [CDLesson]) -> [UUID: CDLesson] {
        var cache: [UUID: CDLesson] = [:]
        for ordered in orderedSequenceGroups(lessons) {
            for index in ordered.indices.dropFirst() {
                guard let lessonID = ordered[index].id, cache[lessonID] == nil else { continue }
                cache[lessonID] = ordered[index - 1]
            }
        }
        return cache
    }

    /// Next lesson for every lesson in the library, keyed by lesson id — the
    /// mirror of `buildPrecedingLessonCache`, for the ready queue, which asks
    /// "what comes after this" once per lesson the record holds.
    ///
    /// A lesson last in its sub-area is simply absent from the cache; so is
    /// one filed with no area or no sequence, because "next" has no meaning
    /// without a sub-area to be next *in*.
    nonisolated static func buildNextLessonCache(_ lessons: [CDLesson]) -> [UUID: CDLesson] {
        var cache: [UUID: CDLesson] = [:]
        for ordered in orderedSequenceGroups(lessons) {
            for index in ordered.indices.dropLast() {
                guard let lessonID = ordered[index].id, cache[lessonID] == nil else { continue }
                cache[lessonID] = ordered[index + 1]
            }
        }
        return cache
    }

    /// The library split into sub-areas, each sorted the way the sub-area
    /// reads. Two lessons filed at the same `orderInSequence` would otherwise
    /// take whichever order the fetch returned, so name breaks the tie and
    /// the caches answer the same way twice running.
    nonisolated private static func orderedSequenceGroups(_ lessons: [CDLesson]) -> [[CDLesson]] {
        var groups: [String: [CDLesson]] = [:]
        for lesson in lessons {
            let area = lesson.area.trimmed()
            let sequence = lesson.sequence.trimmed()
            guard !area.isEmpty, !sequence.isEmpty else { continue }
            groups[sequenceGroupKey(area: area, sequence: sequence), default: []].append(lesson)
        }
        return groups.values.map { group in
            group.sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence {
                    return lhs.orderInSequence < rhs.orderInSequence
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// Case-insensitive key matching the `caseInsensitiveCompare` test in
    /// `computePrecedingLesson`. Inputs are already trimmed.
    nonisolated private static func sequenceGroupKey(area: String, sequence: String) -> String {
        area.folding(options: .caseInsensitive, locale: nil)
            + "\u{1F}"
            + sequence.folding(options: .caseInsensitive, locale: nil)
    }
}
