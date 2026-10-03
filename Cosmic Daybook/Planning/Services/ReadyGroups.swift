//
//  ReadyGroups.swift
//  Cosmic Daybook
//
//  Who could be taught together, lesson by lesson.
//
//  The ready queue (`ReadyForNextEngine`) is one row per child and lesson.
//  The guide plans by lesson, so this folds the queue onto the lessons it
//  proposes: a card per lesson with the children ready for it, the ones a
//  practice gate still holds, the ones who could catch up and join, the ones
//  waiting on a confirmation, and whoever already has it on a plan. It reads
//  and proposes; it writes nothing, and it never second-guesses the queue:
//  a child is Ready or Almost here exactly when the queue says so.
//
//  Rules (GROUPS_PAGE_PLAN.md, defaults 1–5):
//  - A group is 2+ ready children (`groups`); one ready child is a single
//    (`singles`); a lesson only gate-held children wait on is `holding`.
//  - Catch-up is derived: a child ready for N appears on next(N)'s card, but
//    only when that card exists. Ghosts never make a card and are never counted.
//  - Unconfirmed children (had the previous lesson, neither confirmed nor
//    mastered, this one neither given nor planned) appear only on group cards,
//    and are never counted.
//  - Order: ready count, then longest wait, then lesson name.
//  - Wait is school days since the evidence lesson was given.
//
//  The builder is `ReadyGroups+Build.swift`.
//

import CoreData
import Foundation

/// One lesson the queue proposes, with everyone who bears on planning it.
nonisolated struct LessonGroup: Sendable, Hashable, Identifiable {

    /// A child the queue holds for this lesson: ready, or almost with a reason.
    struct Member: Sendable, Hashable, Identifiable {
        let child: ReadyRoster.Child
        /// The lesson she was confirmed or mastered on (the previous step).
        let evidenceLessonID: String
        let basis: ReadyForNextItem.Basis
        /// The latest day the evidence lesson was given; nil for an undated mark.
        let basisDate: Date?
        /// School days since `basisDate`; nil when there is no date.
        let waitSchoolDays: Int?
        /// Why she is almost rather than ready; nil when ready.
        let reason: String?

        var id: String { child.id }
    }

    /// A child ready for the previous lesson, who could have it and join this one.
    struct CatchUp: Sendable, Hashable, Identifiable {
        let child: ReadyRoster.Child
        /// The lesson she is ready for now: "could join after <name>".
        let afterLessonID: String
        let afterLessonName: String
        /// Her wait for `afterLessonID`.
        let waitSchoolDays: Int?

        var id: String { child.id }
    }

    /// A child who had the previous lesson and is waiting on the guide's
    /// confirmation. Confirm with `CDLessonAssignment.confirmStudent` on
    /// `assignmentID`.
    struct Unconfirmed: Sendable, Hashable, Identifiable {
        let child: ReadyRoster.Child
        /// Her latest presented assignment of the previous lesson.
        let assignmentID: NSManagedObjectID
        let previousLessonID: String
        /// The latest day she was given the previous lesson.
        let lastGiven: Date?

        var id: String { child.id }
    }

    /// An open plan on this lesson.
    struct Planned: Sendable, Hashable {
        /// The unpresented assignment; nil for year-plan entries.
        let assignmentID: NSManagedObjectID?
        /// Nil for an undated draft or entry.
        let date: Date?
        /// On the roster, by name.
        let children: [ReadyRoster.Child]

        var isYearPlan: Bool { assignmentID == nil }
    }

    let position: LessonSequenceOrder.Position
    /// Ready now, by name.
    let ready: [Member]
    /// Held by the practice gate, by name; never preselected.
    let almost: [Member]
    /// Dashed "could join after N" ghosts, by name; never counted.
    let catchUp: [CatchUp]
    /// "Confirm" lines, by name; only on a group card, never counted.
    let unconfirmed: [Unconfirmed]
    /// Open plans on this lesson, soonest first.
    let plannedWith: [Planned]

    var id: String { position.lessonID }
    var lessonID: String { position.lessonID }
    var lessonUUID: UUID { position.lessonUUID }
    var lessonName: String { position.name }
    var area: String { position.area }
    var sequence: String { position.sequence }
    /// "3 of 7".
    var stepLabel: String { position.stepLabel }

    /// The longest a ready child has waited, in school days; nil when no
    /// ready child has a dated evidence lesson.
    var longestWait: Int? { ready.compactMap(\.waitSchoolDays).max() }

    /// 2+ ready children.
    var isGroup: Bool { ready.count >= ReadyGroups.groupThreshold }

    /// What the Plan sheet preselects: the ready children only.
    var readyStudentUUIDs: Set<UUID> { Set(ready.compactMap(\.child.uuid)) }

    /// The page's order: ready count, then longest wait (none last), then
    /// lesson name, then ID.
    static func precedes(_ lhs: LessonGroup, _ rhs: LessonGroup) -> Bool {
        if lhs.ready.count != rhs.ready.count { return lhs.ready.count > rhs.ready.count }
        let leftWait = lhs.longestWait ?? -1
        let rightWait = rhs.longestWait ?? -1
        if leftWait != rightWait { return leftWait > rightWait }
        let byName = lhs.lessonName.localizedCaseInsensitiveCompare(rhs.lessonName)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.lessonID < rhs.lessonID
    }
}

/// The ready queue folded onto lessons, for the Groups page and Today.
nonisolated struct ReadyGroups: Sendable, Equatable {

    /// How many ready children make a group.
    static let groupThreshold = 2

    /// One area chip: how many group cards and singles it holds.
    struct AreaCount: Sendable, Hashable, Identifiable {
        let area: String
        let groups: Int
        let singles: Int

        var id: String { area }
    }

    /// Every lesson card, in `LessonGroup.precedes` order.
    let lessons: [LessonGroup]
    /// Cards with 2+ ready children, in order.
    let groups: [LessonGroup]
    /// Cards with exactly one ready child, in order: the "N lessons with one
    /// child ready" row.
    let singles: [LessonGroup]
    /// Cards with no ready child, only gate-held ones, in order. Today lists
    /// them (Plan disabled); the Groups page may leave them out.
    let holding: [LessonGroup]
    /// Areas with a group or a single, alphabetically. Counts ignore `inArea`.
    let areaCounts: [AreaCount]

    /// Sorts `lessons` and splits them.
    init(lessons: [LessonGroup], areaCounts: [AreaCount]? = nil) {
        let sorted = lessons.sorted(by: LessonGroup.precedes)
        self.lessons = sorted
        groups = sorted.filter(\.isGroup)
        singles = sorted.filter { $0.ready.count == 1 }
        holding = sorted.filter(\.ready.isEmpty)
        self.areaCounts = areaCounts ?? Self.countAreas(sorted)
    }

    /// The card for a lesson, if the queue proposes it.
    func group(for lessonID: String) -> LessonGroup? {
        lessons.first { $0.lessonID == lessonID }
    }

    /// Only the cards in `area` (case-insensitive); nil keeps all. The area
    /// counts stay whole, so the chips do not change under the selection.
    func inArea(_ area: String?) -> ReadyGroups {
        guard let area else { return self }
        let kept = lessons.filter { $0.area.caseInsensitiveCompare(area) == .orderedSame }
        return ReadyGroups(lessons: kept, areaCounts: areaCounts)
    }

    private static func countAreas(_ lessons: [LessonGroup]) -> [AreaCount] {
        var groups: [String: Int] = [:]
        var singles: [String: Int] = [:]
        for lesson in lessons where !lesson.ready.isEmpty {
            if lesson.isGroup {
                groups[lesson.area, default: 0] += 1
            } else {
                singles[lesson.area, default: 0] += 1
            }
        }
        return Set(groups.keys).union(singles.keys)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { AreaCount(area: $0, groups: groups[$0] ?? 0, singles: singles[$0] ?? 0) }
    }
}
