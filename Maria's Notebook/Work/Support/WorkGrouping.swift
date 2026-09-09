//
//  WorkGrouping.swift
//  Maria's Notebook
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
//  survivors still naming the deleted child (`WorkRepository.deleteWork` does
//  not clean up siblings), and the residue looks exactly like a shared row.
//  Failing the mutual test means such a row degrades to `.shared` and is read
//  as a single row — the conservative answer, and the one that keeps callers
//  from reaching into records that are no longer part of any group.
//

import CoreData
import Foundation

/// How the children on a work item are actually stored.
enum WorkShape: Equatable {
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
struct WorkGroup {
    /// The row this group was resolved from.
    let anchor: CDWorkModel

    /// Every row in the group, `anchor` included, ordered by creation date so
    /// output is stable between calls.
    let members: [CDWorkModel]

    /// Everyone named on `anchor` — its owner plus its participants.
    let studentIDs: [UUID]

    var shape: WorkShape {
        if members.count > 1 {
            return .linkedCopies(total: members.count)
        }
        return studentIDs.count > 1 ? .shared(childCount: studentIDs.count) : .single
    }

    /// The rows other than the anchor.
    var siblings: [CDWorkModel] {
        members.filter { $0 !== anchor }
    }
}

enum WorkGrouping {

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

    // MARK: - What a Child Sees

    /// The rows a child's own work list should show, out of every row that
    /// names her.
    ///
    /// Linked copies each name the whole group, so a naive "everything that
    /// names her" lists the same assignment once per copy. She sees the copy
    /// she owns; a row she is only a passenger on counts only when no member
    /// of its group is hers. The copies themselves keep naming every child —
    /// that mutual naming is what `areLinkedCopies` reads, and what lets
    /// "with Leshem" render on each copy.
    static func visibleWork(
        for studentID: UUID, among works: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        works.filter { work in
            guard involves(studentID, in: work) else { return false }
            if owner(of: work) == studentID { return true }
            let group = group(containing: work, in: context)
            return !group.members.contains { owner(of: $0) == studentID }
        }
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
            studentIDs: studentIDs(of: work)
        )
    }

    /// Walks the mutual-link relation outward from `work`.
    ///
    /// Transitive rather than one hop: a group that has already lost a row is
    /// still connected through the rows that remain, and stopping at one hop
    /// would report a partial group as if it were the whole one.
    private static func closure(
        from work: CDWorkModel, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let candidates = candidateRows(sharingLessonWith: work, in: context)
        guard !candidates.isEmpty else { return [work] }

        var found: [CDWorkModel] = [work]
        var frontier: [CDWorkModel] = [work]

        while let current = frontier.popLast() {
            for candidate in candidates
            where !found.contains(where: { $0 === candidate })
                && areLinkedCopies(current, candidate) {
                found.append(candidate)
                frontier.append(candidate)
            }
        }
        return found
    }

    /// Rows that could plausibly be siblings, narrowed in the fetch so grouping
    /// does not fault the whole work table for every lookup.
    private static func candidateRows(
        sharingLessonWith work: CDWorkModel, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", work.lessonID)
        return context.safeFetch(request).filter { $0 !== work }
    }

    /// Whether two rows are copies of one another created by the same fan-out.
    ///
    /// The mutual naming test carries the weight; the field comparisons only
    /// keep two genuinely separate assignments of the same lesson from being
    /// read as one group.
    static func areLinkedCopies(_ lhs: CDWorkModel, _ rhs: CDWorkModel) -> Bool {
        guard lhs !== rhs,
              let lhsOwner = owner(of: lhs),
              let rhsOwner = owner(of: rhs),
              lhsOwner != rhsOwner else { return false }

        guard studentIDs(of: lhs).contains(rhsOwner),
              studentIDs(of: rhs).contains(lhsOwner) else { return false }

        return lhs.lessonID == rhs.lessonID
            && lhs.presentationID == rhs.presentationID
            && lhs.kind == rhs.kind
            && normalizedTitle(lhs.title) == normalizedTitle(rhs.title)
    }

    /// Whitespace- and accent-insensitive title comparison, matching the rule
    /// `PresentationFollowUpWorkService` already uses to recognise its own work.
    static func normalizedTitle(_ title: String) -> String {
        title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
