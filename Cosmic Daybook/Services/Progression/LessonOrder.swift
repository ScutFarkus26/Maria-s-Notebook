//
//  LessonOrder.swift
//  Cosmic Daybook
//
//  The one order of lessons in a sub-area, and what comes next and before.
//
//  Two lessons can share an `orderInSequence`: older lessons all took 0, and
//  two devices adding a lesson at once can each take max + 1. Until
//  2026-11-21 every screen broke that tie its own way: plan-next, Unlock and
//  the meeting's Complete sorted by order alone (so the fetch decided),
//  Groups and the ready queue by name, the Checklist by `sortIndex` and then
//  name, the Lessons screens and Claude by name and then id. Plan-next could
//  skip a lesson that Groups named as next (domain-logic review R21). Every
//  one of them now asks this: order, then the area-wide `sortIndex`, then
//  name, then id, so no two lessons ever compare equal.
//
//  A sub-area is an area and a sequence, both non-empty, matched trimmed and
//  in any case. A lesson filed without one has no next and no previous.
//
//  A tie is also put right in the store (`renumberTies`): the launch steps
//  and every restore number a tied sub-area 0, 1, 2… in this order, writing
//  only the numbers that change. The order it reads is the same before and
//  after, so two devices doing it at once write the same numbers.
//

import CoreData
import Foundation

/// A lesson as `LessonOrder` compares it.
nonisolated protocol LessonOrderable {
    var lessonOrderKey: LessonOrder.Key { get }
}

nonisolated enum LessonOrder {

    /// What two lessons are compared by, in this order.
    struct Key: Sendable, Hashable {
        let orderInSequence: Int64
        let sortIndex: Int64
        let name: String
        /// The id as a UUID string; empty when the lesson has none.
        let id: String
    }

    // MARK: - Comparing

    /// Order, then `sortIndex`, then name (case-insensitive), then id.
    static func precedes(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id < rhs.id
    }

    static func precedes<Lesson: LessonOrderable>(_ lhs: Lesson, _ rhs: Lesson) -> Bool {
        precedes(lhs.lessonOrderKey, rhs.lessonOrderKey)
    }

    /// `lessons` in taught order.
    static func sorted<Lesson: LessonOrderable>(_ lessons: some Sequence<Lesson>) -> [Lesson] {
        lessons.sorted { precedes($0, $1) }
    }

    // MARK: - Sub-Areas

    /// The key two lessons in one sub-area share: area and sequence, trimmed
    /// and case-folded. Nil when either is empty.
    static func subAreaKey(area: String, sequence: String) -> String? {
        let area = area.trimmed()
        let sequence = sequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty else { return nil }
        return foldedKey(area: area, sequence: sequence)
    }

    /// The same key for names already trimmed and known to be non-empty.
    static func foldedKey(area: String, sequence: String) -> String {
        area.folding(options: .caseInsensitive, locale: nil)
            + "\u{1F}"
            + sequence.folding(options: .caseInsensitive, locale: nil)
    }

    /// The library split into sub-areas, each in taught order. Lessons filed
    /// without an area or a sequence are left out.
    static func subAreas(_ lessons: [CDLesson]) -> [[CDLesson]] {
        var groups: [String: [CDLesson]] = [:]
        for lesson in lessons {
            guard let key = subAreaKey(area: lesson.area, sequence: lesson.sequence) else { continue }
            groups[key, default: []].append(lesson)
        }
        return groups.values.map { sorted($0) }
    }

    /// The lessons of `lesson`'s sub-area among `lessons`, in taught order.
    /// Empty when it has no sub-area.
    static func subArea(of lesson: CDLesson, in lessons: [CDLesson]) -> [CDLesson] {
        guard let key = subAreaKey(area: lesson.area, sequence: lesson.sequence) else { return [] }
        return sorted(lessons.filter { subAreaKey(area: $0.area, sequence: $0.sequence) == key })
    }

    /// The lesson after `lesson` in its sub-area, or nil at the end or with
    /// no sub-area.
    static func next(after lesson: CDLesson, in lessons: [CDLesson]) -> CDLesson? {
        let ordered = subArea(of: lesson, in: lessons)
        guard let index = ordered.firstIndex(where: { $0.id == lesson.id }), index + 1 < ordered.count
        else { return nil }
        return ordered[index + 1]
    }

    /// The lesson before `lesson` in its sub-area, or nil at the start or
    /// with no sub-area.
    static func previous(before lesson: CDLesson, in lessons: [CDLesson]) -> CDLesson? {
        let ordered = subArea(of: lesson, in: lessons)
        guard let index = ordered.firstIndex(where: { $0.id == lesson.id }), index > 0 else { return nil }
        return ordered[index - 1]
    }

    // MARK: - Ties

    /// Numbers each sub-area that holds a tie 0, 1, 2… in taught order,
    /// writing only the numbers that change. A sub-area with no tie is left
    /// as it is, gaps and all. Returns how many lessons changed. Does not save.
    @discardableResult
    static func renumberTies(in lessons: [CDLesson]) -> Int {
        var changed = 0
        for ordered in subAreas(lessons) {
            let numbers = ordered.map(\.orderInSequence)
            guard Set(numbers).count < numbers.count else { continue }
            changed += renumber(ordered)
        }
        return changed
    }

    /// Writes 0, 1, 2… as `orderInSequence` in the given order, touching only
    /// lessons whose number changes. Returns how many changed. Every move in
    /// a sub-area (the drag, Move Earlier/Later, Claude's `reorder_lessons`)
    /// ends here.
    @discardableResult
    static func renumber(_ ordered: [CDLesson]) -> Int {
        var changed = 0
        for (index, lesson) in ordered.enumerated() where lesson.orderInSequence != Int64(index) {
            lesson.orderInSequence = Int64(index)
            changed += 1
        }
        return changed
    }
}

// MARK: - What Is Compared

nonisolated extension CDLesson: LessonOrderable {
    var lessonOrderKey: LessonOrder.Key {
        LessonOrder.Key(
            orderInSequence: orderInSequence, sortIndex: sortIndex, name: name, id: id?.uuidString ?? ""
        )
    }
}

nonisolated extension CurriculumLessonRef: LessonOrderable {
    var lessonOrderKey: LessonOrder.Key {
        LessonOrder.Key(
            orderInSequence: Int64(orderInSequence), sortIndex: Int64(sortIndex), name: name, id: id.uuidString
        )
    }
}
