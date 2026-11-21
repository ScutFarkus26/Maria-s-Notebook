//
//  WorkGrouping.swift
//  Cosmic Daybook
//
//  Telling a fan-out group apart from a genuinely shared work item.
//
//  Multi-student work exists in two shapes, and the schema enforces neither:
//
//  - *Linked copies.* `assign_work` and the Quick New Work sheet create one
//    `CDWorkModel` per child and then give each row a participant row naming
//    every other child. Three children means three rows, each listing all
//    three.
//  - *A shared row.* `SessionWorkAssignmentService` puts several children on
//    one row. Project-session and book-club work is built this way on purpose.
//
//  Read one row on its own and the two are indistinguishable — which is how a
//  guide ends up believing a fan-out group is a single item. Nothing records
//  which shape a row belongs to, so it has to be recovered from the rows
//  themselves.
//
//  The recovery test is mutual naming: two rows are linked copies only if each
//  one's participants name the other's owner. A one-directional link is not
//  enough. That matters because deleting one row of a fan-out group leaves the
//  survivors still naming the deleted child (only `WorkDeletionService` cleans
//  up siblings, and older builds deleted without it), and the residue looks
//  exactly like a shared row.
//  Failing the mutual test means such a row degrades to `.shared` and is read
//  as a single row — the conservative answer, and the one that keeps callers
//  from reaching into records that are no longer part of any group.
//
//  Mutual naming alone can't tell one fan-out from the next, though. The same
//  work given to the same children twice — an assign_work call weeks after
//  the first — names the same owners both times, so the second assignment
//  used to join the first: a check-in, a status or a delete on the new rows
//  reached the old ones too. So copies must also have been made together:
//  created within `fanOutWindow` of each other. Only Quick New Work and
//  assign_work make copies that name each other, both in one pass, and backup
//  restore and sync keep `createdAt`.
//
//  When both rows have a creation date, the window decides, with the mutual
//  naming, the lesson and the kind. The presentation and the title don't:
//  `createWork` links each copy to *that child's* latest presentation of the
//  lesson, so two children who had it on different days get copies with
//  different presentations, and the work editor used to rename one copy
//  without the others. Either way the copies stopped grouping, and each one
//  read as a shared row for both children.
//
//  One fan-out never gives a child two copies, so a window that holds two
//  rows for one child holds more than one assignment (two pieces of work for
//  the same lesson given to the same children a few seconds apart). Only then
//  do the title and the presentation come back in: each child's copy is her
//  row with the same title, then the same presentation, then the closest
//  creation time, which keeps "Label the parts" and "Write a definition"
//  apart. A pair with no creation date keeps the old rule (the same title and
//  the same presentation), so older group work still groups.
//
//  Project-session rows are shared rows by construction, never copies, even
//  when two of them end up naming the same children.
//
//  Since schema 25 a row carries the answer (domain logic review 2026-11-20,
//  R22): `assignmentID`, which every copy made in one assignment shares, and
//  `isSharedRow`. A row that has them is matched by them, and the recovery
//  above is only the guess for a row not filled yet (`WorkAssignmentFill`
//  writes the guess down at launch and after a restore). Whose a row is, is
//  `WorkOwnership`'s rule.
//

import CoreData
import Foundation

/// How the children on a work item are actually stored.
nonisolated enum WorkShape: Equatable {
    /// One child on one row.
    case single

    /// One row carrying several children. Project-session and book-club work
    /// is built this way; so is the residue left when a linked copy is deleted.
    case shared(childCount: Int)

    /// One of several rows created together, one per child, each listing the
    /// whole group.
    case linkedCopies(total: Int)
}

/// A work item together with the rows it was created alongside.
nonisolated struct WorkGroup {
    /// The row this group was resolved from.
    let anchor: CDWorkModel

    /// Every row in the group, `anchor` included, ordered by creation date so
    /// output is stable between calls.
    let members: [CDWorkModel]

    /// Everyone named on `anchor` — its owner plus its participants.
    let studentIDs: [UUID]

    /// Whether `anchor` is a row its children share (`WorkOwnership.isShared`).
    let isSharedRow: Bool

    var shape: WorkShape {
        if members.count > 1 {
            return .linkedCopies(total: members.count)
        }
        return isSharedRow && studentIDs.count > 1 ? .shared(childCount: studentIDs.count) : .single
    }

    /// The rows other than the anchor.
    var siblings: [CDWorkModel] {
        members.filter { $0 !== anchor }
    }
}

nonisolated enum WorkGrouping {

    // MARK: - Membership

    /// The owner named in the row's `studentID` field, if it holds a uuid.
    ///
    /// Offered project work legitimately carries an empty `studentID` until a
    /// child claims it, so an absent owner is a valid state, not a fault.
    static func owner(of work: CDWorkModel) -> UUID? {
        UUID(uuidString: work.studentID)
    }

    /// Everyone on a work item: the owner first, then participants, deduplicated.
    ///
    /// `CDWorkModel.studentID` and the participant rows overlap — `createWork`
    /// writes both for the owner — so the two have to be unioned rather than
    /// concatenated. This is the same rule the MCP read tools apply, kept here
    /// so the write paths cannot drift from what the guide was shown.
    static func studentIDs(of work: CDWorkModel) -> [UUID] {
        var ids: [UUID] = []
        if let owner = owner(of: work) {
            ids.append(owner)
        }
        let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        for participant in participants {
            guard let id = UUID(uuidString: participant.studentID), !ids.contains(id) else { continue }
            ids.append(id)
        }
        return ids
    }

    static func involves(_ studentID: UUID, in work: CDWorkModel) -> Bool {
        studentIDs(of: work).contains(studentID)
    }

    // MARK: - Grouping

    /// Resolves the fan-out group a work item belongs to.
    ///
    /// Returns a group of one for a shared row, a single-child row, or a row
    /// whose siblings have been deleted — anything that fails the mutual test.
    static func group(
        containing work: CDWorkModel, in context: NSManagedObjectContext
    ) -> WorkGroup {
        let members = closure(from: work, in: context)
        return WorkGroup(
            anchor: work,
            members: members.sorted {
                let lhs = $0.createdAt ?? .distantPast
                let rhs = $1.createdAt ?? .distantPast
                if lhs != rhs { return lhs < rhs }
                return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
            },
            studentIDs: studentIDs(of: work),
            isSharedRow: WorkOwnership.isShared(work) { members }
        )
    }

    /// Walks the mutual-link relation outward from `work`.
    ///
    /// Transitive rather than one hop: a group that has already lost a row is
    /// still connected through the rows that remain, and stopping at one hop
    /// would report a partial group as if it were the whole one.
    ///
    /// When the walk reaches two rows owned by one child, it has crossed from
    /// one assignment into another made in the same minute (see the file
    /// comment), and `sameMinuteGroup` picks this row's own copies out of it.
    private static func closure(
        from work: CDWorkModel, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        closure(from: work, among: candidateRows(for: work, in: context))
    }

    /// The copies made with `work`, itself included, out of rows already in
    /// hand: `candidates` are the other rows on the work's lesson
    /// (`WorkOwnership.Reader` passes them).
    ///
    /// A row that carries its assignment is matched by it: its copies are the
    /// rows with the same `assignmentID`, whatever their titles, days or
    /// presentations have become since. A row not filled yet falls back to
    /// the guess.
    static func closure(
        from work: CDWorkModel, among candidates: [CDWorkModel]
    ) -> [CDWorkModel] {
        guard WorkOwnership.isFilled(work) else { return guessedClosure(from: work, among: candidates) }
        return [work] + candidates.filter { $0 !== work && !$0.isDeleted && $0.assignmentID == work.assignmentID }
    }

    /// The guess: the walk over the mutual-link relation, for a row with no
    /// `assignmentID`. `WorkAssignmentFill` stamps what this finds.
    static func guessedClosure(
        from work: CDWorkModel, among candidates: [CDWorkModel]
    ) -> [CDWorkModel] {
        guard !candidates.isEmpty else { return [work] }

        let linked = walk(from: work, among: candidates, linkedBy: areLinkedCopies)
        guard hasRepeatedOwner(linked) else { return linked }
        return sameMinuteGroup(of: work, among: linked)
    }

    /// The anchor's group out of rows that hold more than one assignment.
    /// For each other child, her row that best matches the anchor (the same
    /// title, then the same presentation, then the closest creation time,
    /// since one pass stamps its copies milliseconds apart), kept only when
    /// the anchor is in turn the best match for her row among its owner's
    /// rows. A tie keeps neither, so an unclear row reads as it did before:
    /// on its own.
    private static func sameMinuteGroup(of work: CDWorkModel, among linked: [CDWorkModel]) -> [CDWorkModel] {
        guard let anchorOwner = owner(of: work) else { return [work] }
        var rowsByOwner: [UUID: [CDWorkModel]] = [:]
        for row in linked {
            guard let rowOwner = owner(of: row) else { continue }
            rowsByOwner[rowOwner, default: []].append(row)
        }
        let anchorOwnersRows = rowsByOwner[anchorOwner] ?? [work]
        var members = [work]
        for (rowOwner, rows) in rowsByOwner where rowOwner != anchorOwner {
            guard let match = bestMatch(for: work, among: rows),
                  bestMatch(for: match, among: anchorOwnersRows) === work else { continue }
            members.append(match)
        }
        return members
    }

    /// The row among `rows` linked to `row` that matches it best, or nil when
    /// none is linked or two match equally well.
    private static func bestMatch(for row: CDWorkModel, among rows: [CDWorkModel]) -> CDWorkModel? {
        let ranked = rows
            .filter { areLinkedCopies(row, $0) }
            .map { (row: $0, rank: matchRank(row, $0)) }
            .sorted { $0.rank > $1.rank }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, !(ranked[1].rank < best.rank) { return nil }
        return best.row
    }

    /// How alike two rows are, best first when compared with `>`: the same
    /// title counts most, then the same presentation, then how close
    /// together they were created.
    private nonisolated struct MatchRank: Comparable {
        let sameTitle: Bool
        let samePresentation: Bool
        let secondsApart: TimeInterval

        static func < (lhs: MatchRank, rhs: MatchRank) -> Bool {
            if lhs.sameTitle != rhs.sameTitle { return !lhs.sameTitle }
            if lhs.samePresentation != rhs.samePresentation { return !lhs.samePresentation }
            return lhs.secondsApart > rhs.secondsApart
        }
    }

    private static func matchRank(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> MatchRank {
        let apart: TimeInterval
        if let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt {
            apart = abs(lhsCreated.timeIntervalSince(rhsCreated))
        } else {
            apart = .greatestFiniteMagnitude
        }
        return MatchRank(
            sameTitle: lhs.title.foldedKey() == rhs.title.foldedKey(),
            samePresentation: lhs.presentationID == rhs.presentationID,
            secondsApart: apart
        )
    }

    private static func walk(
        from work: CDWorkModel, among candidates: [CDWorkModel],
        linkedBy isLinked: (CDWorkModel, CDWorkModel) -> Bool
    ) -> [CDWorkModel] {
        var found: [CDWorkModel] = [work]
        var frontier: [CDWorkModel] = [work]

        while let current = frontier.popLast() {
            for candidate in candidates
            where !found.contains(where: { $0 === candidate })
                && isLinked(current, candidate) {
                found.append(candidate)
                frontier.append(candidate)
            }
        }
        return found
    }

    /// Whether some child owns more than one of `rows`, which one fan-out
    /// never makes.
    private static func hasRepeatedOwner(_ rows: [CDWorkModel]) -> Bool {
        var owners = Set<UUID>()
        for row in rows {
            guard let owner = owner(of: row) else { continue }
            if !owners.insert(owner).inserted { return true }
        }
        return false
    }

    /// Rows that could plausibly be siblings, narrowed in the fetch so grouping
    /// does not fault the whole work table for every lookup: the rows with
    /// the work's `assignmentID`, or, for a row not filled yet, the rows on
    /// its lesson.
    private static func candidateRows(
        for work: CDWorkModel, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        if let assignmentID = work.assignmentID, !assignmentID.isEmpty {
            request.predicate = NSPredicate(format: "assignmentID == %@", assignmentID)
        } else {
            request.predicate = NSPredicate(format: "lessonID == %@", work.lessonID)
        }
        return context.safeFetch(request).filter { $0 !== work }
    }

    /// Whether two rows could be copies of one another created by the same
    /// fan-out.
    ///
    /// The mutual naming test carries the weight; the lesson, the kind and
    /// `wereMadeTogether` keep two genuinely separate assignments of the same
    /// lesson — or the same assignment given twice — from being read as one
    /// group. A pair that passes can still belong to two assignments made in
    /// the same minute; `group(containing:in:)` sorts that case out.
    static func areLinkedCopies(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> Bool {
        guard lhs !== rhs,
              let lhsOwner = owner(of: lhs),
              let rhsOwner = owner(of: rhs),
              lhsOwner != rhsOwner else { return false }

        guard lhs.sourceContextType != .projectSession,
              rhs.sourceContextType != .projectSession else { return false }

        guard studentIDs(of: lhs).contains(rhsOwner),
              studentIDs(of: rhs).contains(lhsOwner) else { return false }

        return lhs.lessonID == rhs.lessonID
            && lhs.kind == rhs.kind
            && wereMadeTogether(lhs, rhs)
    }

    /// How far apart two copies of one fan-out can have been created.
    /// `assign_work` and Quick New Work make every copy in one pass, so their
    /// stamps are milliseconds apart; a repeat assignment is days or weeks on.
    static let fanOutWindow: TimeInterval = 60

    /// Whether two rows came from the same act of assigning. With both
    /// creation dates, being created within `fanOutWindow` is the test: the
    /// presentation can differ (each child's own latest) and so can the
    /// title (a copy renamed before edits carried to the others). A missing
    /// creation date can't rule a row out, so the pair falls back to the old
    /// test, the same title and the same presentation (or none on both).
    private static func wereMadeTogether(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> Bool {
        guard let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt else {
            return matchOnAssignment(lhs, rhs)
        }
        return abs(lhsCreated.timeIntervalSince(rhsCreated)) <= fanOutWindow
    }

    /// The old test for "the same assignment": the same title, ignoring case,
    /// spacing and accents, and the same presentation (or none on both).
    private static func matchOnAssignment(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> Bool {
        lhs.title.foldedKey() == rhs.title.foldedKey() && lhs.presentationID == rhs.presentationID
    }
}
