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
//  rows themselves (the lowest row id among the copies), so two devices that
//  fill the same rows write the same value; a copy whose sibling already
//  carries an id takes that one.
//
//  A stamp is for good, where the guess corrected itself as rows arrived.
//  So the launch run waits out the first download from iCloud
//  (`FirstDownloadGate`): on a half-downloaded store a copy whose siblings
//  haven't come down yet would be stamped shared.
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
        guard !unfilled.isEmpty else { return 0 }

        // Every row on the lessons concerned: the guess reads a row's
        // siblings, filled or not.
        let lessonRequest = CDFetchRequest(CDWorkModel.self)
        lessonRequest.predicate = NSPredicate(format: "lessonID IN %@", Array(Set(unfilled.map(\.lessonID))))
        lessonRequest.relationshipKeyPathsForPrefetching = ["participants"]
        var rowsByLesson: [String: [CDWorkModel]] = [:]
        for row in context.safeFetch(lessonRequest) where !row.isDeleted {
            rowsByLesson[row.lessonID, default: []].append(row)
        }

        var changed = 0
        for row in unfilled where !WorkOwnership.isFilled(row) {
            let others = (rowsByLesson[row.lessonID] ?? []).filter { $0 !== row }
            let copies = WorkGrouping.guessedClosure(from: row, among: others)
            let id = assignmentID(for: copies)
            // Copies made together are each one child's; only a row with none
            // beside it can be a shared one.
            let shared = copies.count <= 1 && isSharedByItself(row)
            for copy in copies where !WorkOwnership.isFilled(copy) {
                copy.assignmentID = id
                // Only ever set: a flag already on a row (a restore can clear
                // the id and leave the flag) is the row's own word.
                if shared, !copy.isSharedRow { copy.isSharedRow = true }
                changed += 1
            }
        }
        if changed > 0 {
            logger.info("Gave \(changed, privacy: .public) work row(s) their assignment")
        }
        return changed
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

    /// The id a group of copies shares: one a copy already carries (the
    /// lowest, should two disagree), else the lowest row id among them, so
    /// every device works out the same one.
    private static func assignmentID(for copies: [CDWorkModel]) -> String {
        if let carried = copies.compactMap(\.assignmentID).filter({ !$0.isEmpty }).min() { return carried }
        return copies.compactMap { $0.id?.uuidString }.min() ?? UUID().uuidString
    }

    /// A row with no copies beside it is shared when it is project-session
    /// work, or names more than one child.
    private static func isSharedByItself(_ row: CDWorkModel) -> Bool {
        row.sourceContextType == .projectSession || WorkGrouping.studentIDs(of: row).count > 1
    }
}
