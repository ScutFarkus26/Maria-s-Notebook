// ReadyBacklog.swift
// How the ready-to-present backlog turns presentations into rows: one row per
// lesson, ordered by the child who has waited longest.
//
// The backlog used to draw one card per presentation, so a lesson planned for
// three groups was three cards scattered through the grid, and nothing on any
// card said which children had gone longest without a lesson — the one thing
// the rail beside it is there to answer. Grouping by lesson and sorting by the
// longest wait puts the lesson that serves the long-waiters at the top.
//
// The rules are pure and take closures rather than managed objects, so the
// grouping, the order and the counts are testable without a store.

import Foundation

/// One lesson's row: every visible presentation of that lesson, in the order
/// they arrived, and the longest wait among their children.
nonisolated struct BacklogLessonGroup<Item>: Identifiable {
    let lessonID: UUID
    /// The presentations ("groups" to the guide) of this lesson, oldest first.
    let items: [Item]
    /// The longest wait among every child on any of `items`, in school days.
    /// `ReadyBacklog.neverTaught` for a child never taught; nil when no child
    /// has a known wait.
    let longestWait: Int?

    var id: UUID { lessonID }
}

nonisolated enum ReadyBacklog {

    /// The wait `PresentationsViewModel.daysSinceLastLessonByStudent` stores
    /// for a child who has never been taught.
    static let neverTaught = Int.max

    /// Groups `items` by lesson. Groups keep the order of their first item, so
    /// an age-ordered input gives oldest-lesson-first rows; with
    /// `longestWaitFirst` they are then reordered by the longest wait among
    /// their children, descending, with that age order breaking ties.
    static func groupByLesson<Item>(
        _ items: [Item],
        lessonID: (Item) -> UUID,
        studentIDs: (Item) -> [UUID],
        waits: [UUID: Int],
        longestWaitFirst: Bool
    ) -> [BacklogLessonGroup<Item>] {
        var order: [UUID] = []
        var itemsByLesson: [UUID: [Item]] = [:]
        var waitByLesson: [UUID: Int] = [:]
        for item in items {
            let id = lessonID(item)
            if itemsByLesson[id] == nil { order.append(id) }
            itemsByLesson[id, default: []].append(item)
            if let wait = longestWait(among: studentIDs(item), waits: waits) {
                waitByLesson[id] = max(waitByLesson[id] ?? wait, wait)
            }
        }
        let groups = order.map { id in
            BacklogLessonGroup(lessonID: id, items: itemsByLesson[id] ?? [], longestWait: waitByLesson[id])
        }
        guard longestWaitFirst else { return groups }
        // Sorting the enumerated pairs keeps the sort stable: Swift's `sorted`
        // promises nothing about equal elements, and equal waits are common.
        return groups.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.longestWait ?? -1
                let right = rhs.element.longestWait ?? -1
                if left != right { return left > right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The longest wait among `studentIDs`; nil when none has a known wait.
    static func longestWait(among studentIDs: [UUID], waits: [UUID: Int]) -> Int? {
        studentIDs.compactMap { waits[$0] }.max()
    }

    /// True when a child has waited at least `threshold` school days, or has
    /// never been taught. The threshold is the guide's own Lesson Age
    /// "overdue" setting, so a tinted chip here means what the red bar in the
    /// Waiting Longest rail means.
    static func isLongWait(_ days: Int, threshold: Int) -> Bool {
        days >= max(0, threshold)
    }

    /// The few characters after a long-waiting child's name: the days, or
    /// "new" for a child never taught.
    static func waitBadge(forDays days: Int) -> String {
        days == neverTaught ? "new" : "\(days)"
    }

    /// How many rows `items` make: the distinct lessons among them.
    static func lessonCount<Item>(_ items: [Item], lessonID: (Item) -> UUID) -> Int {
        Set(items.map(lessonID)).count
    }
}
