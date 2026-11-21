//
//  WorkOwnership.swift
//  Cosmic Daybook
//
//  Whose a work row is: the one rule (domain logic review 2026-11-20, R22).
//
//  A row counts as a child's when
//
//  - she owns it (`studentID` names her): her own work, or her copy of work
//    given to a group; or
//  - she is named on it and owns no copy of its assignment: a row its
//    children share (project and book-club work, offered work the children
//    claim), or a classmate's row she is on with none of her own beside it.
//
//  A classmate's copy that names her is not hers while she has her own:
//  linked copies each list the whole group, so being named is not enough.
//
//  "Its assignment" is the row's `assignmentID` (schema 25), which every copy
//  made in one assignment shares. It is stamped when the row is made
//  (`WorkRepository.createWork`, `WorkAssignmentService`) and filled on older
//  rows at launch and after a restore (`WorkAssignmentFill`). A row not
//  filled yet is read by `WorkGrouping`'s guess, which is what the fill
//  writes down. A row its children share (`isSharedRow`, and project-session
//  work by construction) has no copies, so it counts for everyone on it
//  without a look at the rest.
//
//  Before this there were five rules: `WorkGrouping.visibleWork` and
//  `WorkVisibility` (this rule, resting on the guess), the Class Grid's
//  `ownWork` (by lesson, not by assignment), readiness's `gatingWork` and
//  `workInvolvesStudent` (which dropped a shared row beside her own work, and
//  let a classmate's copy gate a child who owned nothing among the rows in
//  hand), and owner-only reads in Today and the meetings (which never showed
//  shared project work for the other children on it).
//

import CoreData
import Foundation

nonisolated enum WorkOwnership {

    // MARK: - The rule

    /// The rule, from plain values. The Class Grid's background snapshot
    /// reads this too (`work(of:among:)` over `CurriculumWorkRef`), so a cell
    /// and a list can't disagree.
    ///
    /// - Parameters:
    ///   - isSharedRow: the row is one its children share, so it has no copies.
    ///   - ownsACopy: she owns another row of this row's assignment.
    static func counts(
        for studentID: UUID, ownerID: UUID?, namedIDs: some Sequence<UUID>,
        isSharedRow: Bool, ownsACopy: Bool
    ) -> Bool {
        if ownerID == studentID { return true }
        guard namedIDs.contains(studentID) else { return false }
        return isSharedRow || !ownsACopy
    }

    /// Whether the row carries its assignment: every row does once
    /// `WorkAssignmentFill` has run on it.
    static func isFilled(_ work: CDWorkModel) -> Bool {
        !(work.assignmentID ?? "").isEmpty
    }

    /// Whether `work` is a row its children share, as the fill stamps it:
    /// project-session work and a row flagged shared always, a filled row
    /// with no flag never, and a row not filled yet by the guess (`copies`
    /// are the rows made together with it, itself included).
    static func isShared(_ work: CDWorkModel, guessedCopies copies: () -> [CDWorkModel]) -> Bool {
        if work.sourceContextType == .projectSession || work.isSharedRow { return true }
        if isFilled(work) { return false }
        return WorkGrouping.studentIDs(of: work).count > 1 && copies().count <= 1
    }

    // MARK: - One row

    /// Whether `work` is a row its children share. One fetch of its lesson's
    /// rows, only for a row not filled yet that names several children.
    static func isShared(_ work: CDWorkModel, in context: NSManagedObjectContext) -> Bool {
        isShared(work) { WorkGrouping.group(containing: work, in: context).members }
    }

    /// Whether `work` counts as `studentID`'s. One fetch of the row's copies,
    /// only for a classmate's row that names her and isn't a shared one.
    static func isWork(_ work: CDWorkModel, of studentID: UUID, in context: NSManagedObjectContext) -> Bool {
        let owner = WorkGrouping.owner(of: work)
        if owner == studentID { return true }
        let named = WorkGrouping.studentIDs(of: work)
        guard named.contains(studentID) else { return false }
        if work.sourceContextType == .projectSession || work.isSharedRow { return true }
        let copies = WorkGrouping.group(containing: work, in: context).members
        return !copies.contains { WorkGrouping.owner(of: $0) == studentID }
    }

    /// The children `work` counts for, owner first. At most one fetch, of the
    /// row's copies; a screen reading many rows uses a `Reader`.
    static func students(of work: CDWorkModel, in context: NSManagedObjectContext) -> [UUID] {
        let named = WorkGrouping.studentIDs(of: work)
        guard named.count > 1 else { return named }
        if work.sourceContextType == .projectSession || work.isSharedRow { return named }
        let owner = WorkGrouping.owner(of: work)
        let copyOwners = Set(
            WorkGrouping.group(containing: work, in: context).members.compactMap(WorkGrouping.owner(of:))
        )
        return named.filter { $0 == owner || !copyOwners.contains($0) }
    }

    /// The children `work` counts for, read through the row's own context:
    /// for a caller that holds rows and no context. A row in no context
    /// counts for everyone it names.
    static func students(of work: CDWorkModel) -> [UUID] {
        guard let context = work.managedObjectContext else { return WorkGrouping.studentIDs(of: work) }
        return students(of: work, in: context)
    }

    /// The rows among `works` that count as `studentID`'s, in their order.
    static func work(
        of studentID: UUID, among works: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        works.filter { isWork($0, of: studentID, in: context) }
    }

    // MARK: - The Class Grid's snapshot

    /// The rows among `refs` that count as `studentID`'s, in their order: the
    /// same rule over the background snapshot. `refs` are the rows on the
    /// lessons being read, so a copy's siblings are among them.
    static func work(of studentID: UUID, among refs: [CurriculumWorkRef]) -> [CurriculumWorkRef] {
        let naming = refs.filter { $0.ownerID == studentID || $0.studentIDs.contains(studentID) }
        let owned = Set(naming.filter { $0.ownerID == studentID }.map(\.assignment))
        return naming.filter { ref in
            counts(
                for: studentID, ownerID: ref.ownerID, namedIDs: ref.studentIDs,
                isSharedRow: ref.isSharedRow, ownsACopy: owned.contains(ref.assignment)
            )
        }
    }

    // MARK: - Many rows

    /// The rule for a screen that reads many rows at once (the checklist's
    /// cells, the Work column and its child filter, the Works log): the rows
    /// are taken once, so a screen's worth costs one fetch, and each row's
    /// copies are remembered.
    nonisolated final class Reader {
        private let rowsByLesson: [String: [CDWorkModel]]
        private let rowsByAssignment: [String: [CDWorkModel]]
        private var copiesByRow: [ObjectIdentifier: [CDWorkModel]] = [:]

        /// - Parameter rows: every row of the lessons the screen reads, open
        ///   and closed, whoever owns it: a child's closed copy is what tells
        ///   her classmate's open copy apart from a row she shares.
        init(rows: some Sequence<CDWorkModel>) {
            var byLesson: [String: [CDWorkModel]] = [:]
            var byAssignment: [String: [CDWorkModel]] = [:]
            for row in rows where !row.isDeleted {
                byLesson[row.lessonID, default: []].append(row)
                if let assignmentID = row.assignmentID, !assignmentID.isEmpty {
                    byAssignment[assignmentID, default: []].append(row)
                }
            }
            rowsByLesson = byLesson
            rowsByAssignment = byAssignment
        }

        /// `works`, plus every row on the lessons where one of them names
        /// more than one child, in one fetch. A row naming one child is that
        /// child's whatever else is on its lesson, so its lesson needn't be
        /// read.
        convenience init(covering works: [CDWorkModel], in context: NSManagedObjectContext) {
            let lessonIDs = Set(works.filter { WorkGrouping.studentIDs(of: $0).count > 1 }.map(\.lessonID))
            guard !lessonIDs.isEmpty else {
                self.init(rows: works)
                return
            }
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
            request.relationshipKeyPathsForPrefetching = ["participants"]
            var seen = Set<ObjectIdentifier>()
            let rows = (works + context.safeFetch(request)).filter { seen.insert(ObjectIdentifier($0)).inserted }
            self.init(rows: rows)
        }

        /// The copies of `work`'s assignment, itself included: the rows with
        /// its `assignmentID`, or the guess for a row not filled yet.
        func copies(of work: CDWorkModel) -> [CDWorkModel] {
            let key = ObjectIdentifier(work)
            if let known = copiesByRow[key] { return known }
            let copies: [CDWorkModel]
            if let assignmentID = work.assignmentID, !assignmentID.isEmpty {
                copies = [work] + (rowsByAssignment[assignmentID] ?? []).filter { $0 !== work }
            } else {
                copies = WorkGrouping.guessedClosure(
                    from: work, among: (rowsByLesson[work.lessonID] ?? []).filter { $0 !== work }
                )
            }
            copiesByRow[key] = copies
            return copies
        }

        /// What names `work`'s assignment for the snapshot: its
        /// `assignmentID`, or what the fill would give it.
        func assignment(of work: CDWorkModel) -> String {
            if let assignmentID = work.assignmentID, !assignmentID.isEmpty { return assignmentID }
            return copies(of: work).compactMap { $0.id?.uuidString }.min()
                ?? work.objectID.uriRepresentation().absoluteString
        }

        /// Whether `work` is a row its children share.
        func isShared(_ work: CDWorkModel) -> Bool {
            WorkOwnership.isShared(work) { copies(of: work) }
        }

        /// Whether `work` counts as `studentID`'s.
        func isWork(_ work: CDWorkModel, of studentID: UUID) -> Bool {
            let owner = WorkGrouping.owner(of: work)
            if owner == studentID { return true }
            let named = WorkGrouping.studentIDs(of: work)
            guard named.contains(studentID) else { return false }
            if work.sourceContextType == .projectSession || work.isSharedRow { return true }
            return !copies(of: work).contains { WorkGrouping.owner(of: $0) == studentID }
        }

        /// Whether `work` is `studentID`'s alone: she owns it, and it isn't a
        /// row she shares. Logging it closes it for her and nobody else.
        func isHersAlone(_ work: CDWorkModel, _ studentID: UUID) -> Bool {
            guard WorkGrouping.owner(of: work) == studentID else { return false }
            return !(WorkGrouping.studentIDs(of: work).count > 1 && isShared(work))
        }

        /// The children `work` counts for, owner first.
        func students(of work: CDWorkModel) -> [UUID] {
            let named = WorkGrouping.studentIDs(of: work)
            guard named.count > 1 else { return named }
            return named.filter { isWork(work, of: $0) }
        }
    }
}
