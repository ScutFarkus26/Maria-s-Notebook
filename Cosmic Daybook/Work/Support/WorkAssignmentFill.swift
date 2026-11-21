//
//  WorkAssignmentFill.swift
//  Cosmic Daybook
//
//  Gives older work rows their assignment (schema 25, domain logic review
//  2026-11-20, R22): `assignmentID`, which every copy made in one assignment
//  shares, and `isSharedRow`, which says the row is one its children share.
//
//  New rows are stamped as they are made (`WorkRepository.createWork`,
//  `WorkAssignmentService`). Rows from before schema 25, rows another path
//  made without the stamp (project check-ins, a duplicate folded in), and
//  rows a format-46 backup restored have neither. This fill writes down, once,
//  what `WorkGrouping`'s guess says about them: which rows were made together
//  (named each other, created within a minute), and whether a row naming
//  several children with no copies beside it is a shared one.
//
//  It keys on the nil, never on a one-time flag (plan "Domain logic fixes",
//  Decision 19), so it runs at every launch and after every restore, and a
//  second run finds nothing. The id it gives a group is worked out from the
//  rows themselves (the lowest of the copies' row ids and the ids they
//  already carry), so two devices that fill the same rows write the same
//  value.
//
//  The launch run waits out the first download from iCloud
//  (`FirstDownloadGate`), but a copy can still come down after the rest were
//  filled, and two devices can each fill a different part of one group. So
//  the run also looks again at what a part-filled group leaves (domain logic
//  Phase 10, cold review finding 5): a row the fill stamped shared, and a
//  group of copies whose owners don't cover the children they name. Where the
//  guess joins rows carrying different ids, every row carrying any of them
//  takes the lowest, and a row with copies beside it loses the shared flag.
//  Ids only ever go down, so every device that has the whole group ends with
//  the same answer.
//

import CoreData
import Foundation
import OSLog

nonisolated enum WorkAssignmentFill {
    private static let logger = Logger.work

    /// Stamps every row that has no `assignmentID`. Returns how many rows it
    /// changed. Synchronous, on `context`'s queue; it doesn't save.
    @discardableResult
    static func run(in context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "assignmentID == nil OR assignmentID == ''")
        request.relationshipKeyPathsForPrefetching = ["participants"]
        let unfilled = context.safeFetch(request).filter { !$0.isDeleted }
        let seeds = unfilled + flaggedShared(in: context) + partGroups(in: context)
        guard !seeds.isEmpty else { return 0 }
        let wasUnfilled = Set(unfilled.map(\.objectID))

        // Every row on the lessons concerned: the guess reads a row's
        // siblings, filled or not.
        let lessonRequest = CDFetchRequest(CDWorkModel.self)
        lessonRequest.predicate = NSPredicate(format: "lessonID IN %@", Array(Set(seeds.map(\.lessonID))))
        lessonRequest.relationshipKeyPathsForPrefetching = ["participants"]
        var rowsByLesson: [String: [CDWorkModel]] = [:]
        for row in context.safeFetch(lessonRequest) where !row.isDeleted {
            rowsByLesson[row.lessonID, default: []].append(row)
        }

        var changed = Set<NSManagedObjectID>()
        for seed in seeds {
            let lessonRows = rowsByLesson[seed.lessonID] ?? []
            let copies = WorkGrouping.guessedClosure(from: seed, among: lessonRows.filter { $0 !== seed })
            // The guess's copies, and every row carrying an id one of them
            // carries, so joining two parts never splits off a third.
            let carried = Set(copies.compactMap(\.assignmentID).filter { !$0.isEmpty })
            let members = copies + lessonRows.filter { row in
                !copies.contains { $0 === row } && carried.contains(row.assignmentID ?? "")
            }
            // A group whose copies already agree keeps its id, whatever it
            // is: only a copy with none, or copies that disagree, are given one.
            let agreed = members.allSatisfy(WorkOwnership.isFilled)
                && Set(members.compactMap(\.assignmentID)).count == 1
            let id = agreed ? (seed.assignmentID ?? "") : assignmentID(for: members)
            // Copies made together are each one child's; only a row with none
            // beside it can be a shared one, and only the fill's first look
            // at a row says so.
            let shared = members.count <= 1 && wasUnfilled.contains(seed.objectID) && isSharedByItself(seed)
            for member in members {
                var touched = false
                if member.assignmentID != id {
                    member.assignmentID = id
                    touched = true
                }
                if members.count > 1, member.isSharedRow {
                    member.isSharedRow = false
                    touched = true
                } else if shared, !member.isSharedRow {
                    // A flag already on a lone row (a restore can clear the id
                    // and leave the flag) is the row's own word.
                    member.isSharedRow = true
                    touched = true
                }
                if touched { changed.insert(member.objectID) }
            }
        }
        if !changed.isEmpty {
            logger.info("Gave \(changed.count, privacy: .public) work row(s) their assignment")
        }
        return changed.count
    }

    /// Filled rows the fill stamped shared (the only writer of the flag),
    /// other than project work, which is shared by construction: a lone copy
    /// stamped before its classmates' copies came down.
    private static func flaggedShared(in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "assignmentID != nil AND assignmentID != '' AND isSharedRow == YES")
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request).filter { !$0.isDeleted && $0.sourceContextType != .projectSession }
    }

    /// One row from each filled group of two or more copies whose owners
    /// don't cover the children the copies name: part of a group, maybe
    /// filled on a device that didn't have the rest. Rows naming one child
    /// can't be copies, so only rows with several participants are read.
    private static func partGroups(in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "assignmentID != nil AND assignmentID != '' AND isSharedRow == NO AND participants.@count > 1"
        )
        request.relationshipKeyPathsForPrefetching = ["participants"]
        var groups: [String: [CDWorkModel]] = [:]
        for row in context.safeFetch(request) where !row.isDeleted && row.sourceContextType != .projectSession {
            groups[row.assignmentID ?? "", default: []].append(row)
        }
        return groups.values.compactMap { rows in
            guard rows.count > 1 else { return nil }
            let owners = Set(rows.compactMap(WorkGrouping.owner))
            let named = Set(rows.flatMap(WorkGrouping.studentIDs))
            return named.isSubset(of: owners) ? nil : rows.first
        }
    }

    /// The launch pass's run, every launch: never while the first download
    /// from iCloud is under way, and never on a pass whose earlier steps left
    /// changes they couldn't save. It saves its own changes. Returns how many
    /// rows it changed, or nil when it didn't run or couldn't save.
    @discardableResult
    static func runIfDue(using context: NSManagedObjectContext, firstDownloadPending: Bool) -> Int? {
        guard !firstDownloadPending, !context.hasChanges else { return nil }
        let changed = run(in: context)
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return nil
        }
        return changed
    }

    /// The id a group of copies shares: the lowest of the ids they carry and
    /// their own row ids. Worked out from the rows alone, so every device that
    /// has the whole group works out the same one, whichever part it filled
    /// first; a copy that comes down later never raises it.
    private static func assignmentID(for copies: [CDWorkModel]) -> String {
        let carried = copies.compactMap(\.assignmentID).filter { !$0.isEmpty }
        return (carried + copies.compactMap { $0.id?.uuidString }).min() ?? UUID().uuidString
    }

    /// A row with no copies beside it is shared when it is project-session
    /// work, or names more than one child.
    private static func isSharedByItself(_ row: CDWorkModel) -> Bool {
        row.sourceContextType == .projectSession || WorkGrouping.studentIDs(of: row).count > 1
    }
}
