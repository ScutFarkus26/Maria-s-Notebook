//
//  ReadyQueueSnapshot.swift
//  Cosmic Daybook
//
//  What the Groups page and the sequence ladder build from, read once.
//
//  The ready queue (`ReadyForNextEngine.items`), the record it came from
//  (`PresentationRecordIndex`), where each lesson sits in its sub-area
//  (`LessonSequenceOrder`) and the roster, as plain values. `ReadyGroups` and
//  `SequenceLadder` are pure functions of this, so a level change rebuilds
//  them from the same snapshot (`filtered(levels:)`) without reading the store.
//

import CoreData
import Foundation

/// The roster the builders consider: who, what to call them, which level.
nonisolated struct ReadyRoster: Sendable, Equatable {

    /// One child, as the builders show her.
    struct Child: Sendable, Hashable, Identifiable {
        /// The student's UUID string, as the record keys her.
        let id: String
        /// "Maya S" (`CDStudent.shortName`).
        let name: String
        let level: CDStudent.Level

        var uuid: UUID? { UUID(uuidString: id) }

        /// By name, then ID, so two children with one short name keep an order.
        static func precedes(_ lhs: Child, _ rhs: Child) -> Bool {
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// studentID → child. A child not in here is not considered at all.
    let children: [String: Child]

    init(_ children: [Child]) {
        var byID: [String: Child] = [:]
        for child in children where byID[child.id] == nil {
            byID[child.id] = child
        }
        self.children = byID
    }

    /// The roster from students already chosen by the caller (enrolled, test
    /// students hidden: `ReadyQueueLoader.students(in:)`).
    init(students: [CDStudent]) {
        self.init(students.compactMap { student in
            student.id.map { Child(id: $0.uuidString, name: student.shortName, level: student.level) }
        })
    }

    func child(_ studentID: String) -> Child? {
        children[studentID]
    }

    /// The levels anyone on the roster is at, for the level picker.
    var levels: Set<CDStudent.Level> {
        Set(children.values.map(\.level))
    }

    /// Only the children at `levels`; nil keeps everyone.
    func filtered(levels: Set<CDStudent.Level>?) -> ReadyRoster {
        guard let levels else { return self }
        return ReadyRoster(children.values.filter { levels.contains($0.level) })
    }
}

/// The inputs `ReadyGroups.build` and `SequenceLadder.build` read.
nonisolated struct ReadyQueueSnapshot: Sendable {
    /// The ready queue, exactly as `ReadyForNextEngine.items` returned it.
    let items: [ReadyForNextItem]
    let index: PresentationRecordIndex
    let order: LessonSequenceOrder
    /// Who is considered. Items, plans and record rows for anyone else are
    /// ignored, which is how the level filter works.
    let roster: ReadyRoster
    /// Lessons given to someone unconfirmed whose own settings don't require
    /// confirmation (`LessonProgressionRules`): a child given one is already in
    /// the queue, so no card offers to confirm her on it.
    let confirmationNotRequired: Set<String>

    init(
        items: [ReadyForNextItem],
        index: PresentationRecordIndex,
        order: LessonSequenceOrder,
        roster: ReadyRoster,
        confirmationNotRequired: Set<String> = []
    ) {
        self.items = items
        self.index = index
        self.order = order
        self.roster = roster
        self.confirmationNotRequired = confirmationNotRequired
    }

    /// Builds the queue itself the way `students_ready` and Today do, over
    /// `students` and the whole library. For a caller that does not already
    /// hold the queue; one that does passes it to the memberwise init.
    @MainActor
    init(
        students: [CDStudent],
        lessons: [CDLesson],
        index: PresentationRecordIndex,
        in context: NSManagedObjectContext
    ) {
        let roster = ReadyRoster(students: students)
        self.init(
            items: ReadyForNextEngine.items(
                studentIDs: Array(roster.children.keys), lessons: lessons, index: index, in: context
            ),
            index: index,
            order: LessonSequenceOrder(lessons: lessons),
            roster: roster,
            confirmationNotRequired: Self.confirmationNotRequired(lessons: lessons, index: index, in: context)
        )
    }

    /// The lessons in `index` given to someone neither confirmed nor mastered
    /// whose settings don't require confirmation. Only those lessons' rules
    /// are resolved, so a library with every gate on reads nothing.
    @MainActor
    static func confirmationNotRequired(
        lessons: [CDLesson],
        index: PresentationRecordIndex,
        in context: NSManagedObjectContext
    ) -> Set<String> {
        let pending = Set(index.givenByLesson.compactMap { lessonID, given in
            given.values.contains { !$0.confirmed && !$0.mastered } ? lessonID : nil
        })
        guard !pending.isEmpty else { return [] }
        let progression = ProgressionRulesLookup(context: context)
        return Set(lessons.compactMap { lesson in
            guard let id = lesson.id?.uuidString, pending.contains(id),
                  !progression.rules(for: lesson).requiresTeacherConfirmation else { return nil }
            return id
        })
    }

    /// The same snapshot with the roster narrowed to `levels` (nil keeps
    /// everyone). Apply it before building: the 2+ threshold counts only the
    /// children left.
    func filtered(levels: Set<CDStudent.Level>?) -> ReadyQueueSnapshot {
        ReadyQueueSnapshot(
            items: items, index: index, order: order, roster: roster.filtered(levels: levels),
            confirmationNotRequired: confirmationNotRequired
        )
    }
}
