//
//  ReadyGroups+Build.swift
//  Cosmic Daybook
//
//  Folding the ready queue onto lessons. The rules are in `ReadyGroups.swift`.
//
//  Cost is one pass over the queue, one over the previous lesson's record
//  per group card, and dictionary lookups: nothing reads the store.
//

import Foundation

nonisolated extension ReadyGroups {

    /// Folds the snapshot's queue onto the lessons it proposes.
    ///
    /// - Parameters:
    ///   - snapshot: the queue and what it was read from. Narrow it with
    ///     `filtered(levels:)` first for a level filter.
    ///   - schoolDaysSince: school days from a day to today, e.g.
    ///     `{ LessonAgeHelper.schoolDaysSinceCreation(createdAt: $0, using: context) }`.
    ///     Called once per queued child with a dated evidence lesson.
    static func build(
        from snapshot: ReadyQueueSnapshot,
        schoolDaysSince: (Date) -> Int
    ) -> ReadyGroups {
        var drafts: [String: (ready: [LessonGroup.Member], almost: [LessonGroup.Member])] = [:]
        var readyMembers: [(member: LessonGroup.Member, lessonID: String)] = []
        for item in snapshot.items {
            guard let child = snapshot.roster.child(item.studentID),
                  snapshot.order.position(of: item.nextLessonID) != nil else { continue }
            let member = LessonGroup.Member(
                child: child,
                evidenceLessonID: item.lessonID,
                basis: item.basis,
                basisDate: item.basisDate,
                waitSchoolDays: item.basisDate.map(schoolDaysSince),
                reason: item.tier == .ready ? nil : item.reasons.joined(separator: "; ")
            )
            if item.tier == .ready {
                drafts[item.nextLessonID, default: ([], [])].ready.append(member)
                readyMembers.append((member, item.nextLessonID))
            } else {
                drafts[item.nextLessonID, default: ([], [])].almost.append(member)
            }
        }

        let catchUps = catchUps(readyMembers, cards: Set(drafts.keys), in: snapshot)
        let cards: [LessonGroup] = drafts.compactMap { lessonID, draft in
            guard let position = snapshot.order.position(of: lessonID) else { return nil }
            let isGroup = draft.ready.count >= groupThreshold
            return LessonGroup(
                position: position,
                ready: draft.ready.sorted { ReadyRoster.Child.precedes($0.child, $1.child) },
                almost: draft.almost.sorted { ReadyRoster.Child.precedes($0.child, $1.child) },
                catchUp: (catchUps[lessonID] ?? []).sorted { ReadyRoster.Child.precedes($0.child, $1.child) },
                unconfirmed: isGroup ? unconfirmed(on: position, in: snapshot) : [],
                plannedWith: planned(on: lessonID, in: snapshot)
            )
        }
        return ReadyGroups(lessons: cards)
    }

    // MARK: - Catch-up

    /// Each ready child on next(N)'s card, when that card exists and she has
    /// neither had next(N) nor been planned for it.
    private static func catchUps(
        _ readyMembers: [(member: LessonGroup.Member, lessonID: String)],
        cards: Set<String>,
        in snapshot: ReadyQueueSnapshot
    ) -> [String: [LessonGroup.CatchUp]] {
        var result: [String: [LessonGroup.CatchUp]] = [:]
        for (member, lessonID) in readyMembers {
            guard let after = snapshot.order.position(of: lessonID),
                  let target = after.nextLessonID, cards.contains(target),
                  snapshot.index.given(student: member.child.id, lesson: target) == nil,
                  !snapshot.index.hasOpenPlan(student: member.child.id, lesson: target) else { continue }
            result[target, default: []].append(LessonGroup.CatchUp(
                child: member.child,
                afterLessonID: after.lessonID,
                afterLessonName: after.name,
                waitSchoolDays: member.waitSchoolDays
            ))
        }
        return result
    }

    // MARK: - Unconfirmed

    /// Children who had the previous lesson, are neither confirmed nor
    /// mastered on it, and have neither had this lesson nor been planned for
    /// it. Only a child with a presented assignment to confirm on is listed:
    /// a bare presentation row has nowhere to hold the confirmation.
    private static func unconfirmed(
        on position: LessonSequenceOrder.Position,
        in snapshot: ReadyQueueSnapshot
    ) -> [LessonGroup.Unconfirmed] {
        guard let previous = position.previousLessonID else { return [] }
        let index = snapshot.index
        let assignments = index.latestPresentedAssignmentByLesson[previous] ?? [:]
        var result: [LessonGroup.Unconfirmed] = []
        for (studentID, given) in index.givenByLesson[previous] ?? [:] where !given.confirmed && !given.mastered {
            guard let child = snapshot.roster.child(studentID),
                  let assignmentID = assignments[studentID],
                  index.given(student: studentID, lesson: position.lessonID) == nil,
                  !index.hasOpenPlan(student: studentID, lesson: position.lessonID) else { continue }
            result.append(LessonGroup.Unconfirmed(
                child: child, assignmentID: assignmentID, previousLessonID: previous, lastGiven: given.days.last
            ))
        }
        return result.sorted { ReadyRoster.Child.precedes($0.child, $1.child) }
    }

    // MARK: - Planned

    /// The lesson's open plans, each with the roster children on it; a plan
    /// naming nobody on the roster is left out.
    private static func planned(on lessonID: String, in snapshot: ReadyQueueSnapshot) -> [LessonGroup.Planned] {
        snapshot.index.openPlans(lesson: lessonID).compactMap { plan in
            let children = plan.studentIDs
                .compactMap(snapshot.roster.child)
                .sorted(by: ReadyRoster.Child.precedes)
            guard !children.isEmpty else { return nil }
            return LessonGroup.Planned(assignmentID: plan.assignmentID, date: plan.date, children: children)
        }
    }
}
