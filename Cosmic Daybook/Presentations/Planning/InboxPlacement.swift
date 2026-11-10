//
//  InboxPlacement.swift
//  Cosmic Daybook
//
//  Which tab of the Inbox an undated lesson sits under: Ready, or Brewing while a
//  child on it hasn't finished the lesson before. The one place that gathers what
//  the blocking check reads and asks it, so Lessons & Work's Inbox
//  (`PresentationsViewModel`) and the Class Grid's Brewing mark
//  (`ClassGridEngine.fillRows`) are answered by the same rule from the same
//  record. `ChecklistBrewingTests` pins that the two agree.
//

import CoreData
import Foundation

enum InboxPlacement {

    typealias Results = [UUID: BlockingAlgorithmEngine.BlockingCheckResult]

    /// The Inbox's rows: plans with no day that haven't been given.
    static func inboxRows(among assignments: [CDLessonAssignment]) -> [CDLessonAssignment] {
        assignments.filter { $0.scheduledFor == nil && !$0.isGiven }
    }

    // MARK: - The Lessons Before

    /// What the check reads off the lesson before each Inbox row, beyond open work.
    /// The Inbox also hashes both, to know when Ready and Brewing need redrawing.
    struct PrecedingRecord {
        /// Closed work on the givings of those lessons. The check needs it: a child
        /// who finished her practice has only closed work there, and with open work
        /// alone she read as having none, so "Waiting for work".
        let closedWork: [CDWorkModel]
        /// lessonID → the children with a mastery mark on it. A mark counts as the
        /// guide's confirmation (bug hunt 2026-11-03 #5).
        let masteryMarks: [String: Set<String>]

        init(
            inboxRows: [CDLessonAssignment],
            lessons: [CDLesson],
            allLessonAssignments: [CDLessonAssignment],
            in context: NSManagedObjectContext
        ) {
            let givings = BlockingAlgorithmEngine.precedingPresentationIDs(
                for: inboxRows, lessons: lessons, allLessonAssignments: allLessonAssignments
            )
            closedWork = InboxPlacement.fetchWork(onGivings: givings, open: false, in: context)
            masteryMarks = InboxPlacement.fetchMasteryMarks(before: inboxRows, lessons: lessons, in: context)
        }
    }

    // MARK: - The Check

    /// Ready or Brewing for each of `inboxRows`, by assignment id, for a caller that
    /// holds the whole assignment table and all open work (the Inbox).
    ///
    /// - Parameters:
    ///   - lessons: every lesson of the rows' sub-areas, so "the lesson before" is
    ///     the one the sub-area's order gives.
    ///   - judgedStudentIDs: the enrolled, shown children. A departed or hidden child
    ///     on a plan doesn't hold it in Brewing.
    static func results( // swiftlint:disable:this function_parameter_count
        inboxRows: [CDLessonAssignment],
        lessons: [CDLesson],
        allLessonAssignments: [CDLessonAssignment],
        openWork: [CDWorkModel],
        preceding: PrecedingRecord,
        judgedStudentIDs: Set<UUID>
    ) -> Results {
        BlockingAlgorithmEngine.checkBlocking(
            forBatch: inboxRows,
            lessons: lessons,
            allLessonAssignments: allLessonAssignments,
            workModels: openWork + preceding.closedWork,
            masteryMarks: preceding.masteryMarks,
            judgedStudentIDs: judgedStudentIDs
        )
    }

    /// The same check for a caller that holds only some lessons' plans (the Class
    /// Grid's rows): it reads the givings of the lessons before, and the work on
    /// them, itself. The check looks at nothing else in the assignment table or the
    /// work, so the answer is the one the Inbox gets from the whole of both.
    static func results(
        inboxRows: [CDLessonAssignment],
        lessons: [CDLesson],
        judgedStudentIDs: Set<UUID>,
        in context: NSManagedObjectContext
    ) -> Results {
        guard !inboxRows.isEmpty else { return [:] }
        let precedingLessonIDs = BlockingAlgorithmEngine.precedingLessonIDs(
            for: inboxRows, precedingLessons: BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        )
        var givings: [CDLessonAssignment] = []
        if !precedingLessonIDs.isEmpty {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID IN %@", Array(precedingLessonIDs))
            givings = context.safeFetch(request).filter(\.isGiven)
        }
        let givingIDs = Set(givings.compactMap { $0.id?.uuidString })
        return results(
            inboxRows: inboxRows,
            lessons: lessons,
            allLessonAssignments: givings,
            openWork: fetchWork(onGivings: givingIDs, open: true, in: context),
            preceding: PrecedingRecord(
                inboxRows: inboxRows, lessons: lessons, allLessonAssignments: givings, in: context
            ),
            judgedStudentIDs: judgedStudentIDs
        )
    }

    // MARK: - Reads

    /// The work that follows the given presentations `givings` (their ids as
    /// strings), open or closed.
    private static func fetchWork(
        onGivings givings: Set<String>, open: Bool, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        guard !givings.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        let status = open
            ? WorkStatus.openPredicate
            : NSCompoundPredicate(notPredicateWithSubpredicate: WorkStatus.openPredicate)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "presentationID IN %@", Array(givings)), status
        ])
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request)
    }

    /// The mastery marks on each row's preceding lesson.
    private static func fetchMasteryMarks(
        before inboxRows: [CDLessonAssignment], lessons: [CDLesson], in context: NSManagedObjectContext
    ) -> [String: Set<String>] {
        let lessonIDs = BlockingAlgorithmEngine.precedingLessonIDs(
            for: inboxRows, precedingLessons: BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        )
        return PresentationRecordIndex.masteryMarks(lessonIDs: lessonIDs, in: context)
    }
}
