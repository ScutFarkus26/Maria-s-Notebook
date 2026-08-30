// QuietStudentsOrder.swift
// Which children the guide has not looked in on, in order.
//
// The Work half's answer to `WaitingStudentsOrder`, and it exists for the same
// reason that one does: the grid beside it can only show children who *have*
// something. A child with no open work has no card anywhere, exactly as a
// never-taught child has no presentation anywhere — and those two absences are
// the ones a guide is least likely to notice on his own.
//
// What it does *not* do is repeat the card. Every open work item already wears
// its own age bar, and sorting the grid by Age already finds the single most
// neglected piece of work. The question only this list can answer is about the
// child: how long since anything of theirs was looked at, and is there anything
// of theirs at all.
//
// The sort itself is `WaitingStudentsOrder`'s, so both columns put the same
// child at the top for the same reason and there is one place to change it.

import CoreData
import Foundation

/// Which children the Work column is showing.
enum QuietStudentsScope: String, CaseIterable, Identifiable, Sendable {
    /// Every enrolled child, however recently their work was checked.
    case everyone
    /// Only children carrying no open work at all.
    case withoutWork

    var id: Self { self }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .withoutWork: "Without Work"
        }
    }

    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let scope = Self(rawValue: rawValue) else { return .everyone }
        return scope
    }
}

enum QuietStudentsOrder {

    // MARK: - Who a work item is open for

    /// Every child this work item is still open for.
    ///
    /// Reading `studentID` alone is the trap here. Group work fans out to
    /// `CDWorkParticipantEntity` rows, so a child in a five-child project can
    /// own none of it — and would be reported as having nothing, which is the
    /// one case this column exists to catch.
    ///
    /// A participant who has finished their part is not counted. The item stays
    /// open for the others, but it is no longer work *that child* is doing, and
    /// `CDWorkModel.isOpen` already draws the line in the same place.
    static func openStudentIDs(of work: CDWorkModel) -> Set<UUID> {
        let owner = UUID(uuidString: work.studentID)
        let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []

        // Work with no participant rows is a single child's, named by `studentID`.
        guard !participants.isEmpty else {
            return Set(owner.map { [$0] } ?? [])
        }

        var ids = Set(
            participants
                .filter { $0.completedAt == nil }
                .compactMap { UUID(uuidString: $0.studentID) }
        )
        // The owner does not always have a participant row of their own. When
        // they have one it decides, completed or not; when they have none the
        // item is still theirs.
        if let owner, !participants.contains(where: { $0.studentID == owner.uuidString }) {
            ids.insert(owner)
        }
        return ids
    }

    // MARK: - How long a child has been quiet

    /// School days since the guide last touched *anything* of each child's.
    ///
    /// The minimum across their open work, not the maximum. The question this
    /// list asks is how long the child has gone unattended, and one item checked
    /// yesterday answers it however long another has sat — that other item is
    /// what the card's own bar and the Age sort are for.
    ///
    /// Children with no open work are simply absent from the result, which
    /// `WaitingStudentsOrder` reads as nothing-to-measure and sorts to the top.
    ///
    /// - Parameter age: school days since that work item was last meaningfully
    ///   touched. Passed in so the caller can supply the count it has already
    ///   made rather than have this walk check-ins and notes a second time.
    static func daysSinceTouchByStudent(
        in works: [CDWorkModel],
        age: (CDWorkModel) -> Int
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for work in works {
            let days = max(0, age(work))
            for id in openStudentIDs(of: work) {
                if let existing = result[id] {
                    result[id] = min(existing, days)
                } else {
                    result[id] = days
                }
            }
        }
        return result
    }

    // MARK: - The list

    /// Orders `students` by who has gone longest without the guide looking at
    /// their work, children carrying nothing first.
    ///
    /// - Parameters:
    ///   - daysSinceTouch: from `daysSinceTouchByStudent`. A child missing from
    ///     it has no open work, which is the top of the list rather than an
    ///     unknown.
    ///   - studentIDsWithOpenWork: used only by `.withoutWork`. It is the
    ///     rollup's own keys — a child is in the map exactly when they have
    ///     something open — so the scope and the labels cannot disagree about
    ///     who is carrying work.
    static func ordered(
        students: [CDStudent],
        daysSinceTouch: [UUID: Int],
        studentIDsWithOpenWork: Set<UUID>,
        scope: QuietStudentsScope,
        search: String = ""
    ) -> [WaitingStudent] {
        WaitingStudentsOrder.ordered(
            students: students,
            daysSince: daysSinceTouch,
            hiding: scope == .withoutWork ? studentIDsWithOpenWork : [],
            search: search
        )
    }
}
