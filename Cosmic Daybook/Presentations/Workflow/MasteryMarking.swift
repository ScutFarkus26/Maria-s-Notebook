//
//  MasteryMarking.swift
//  Cosmic Daybook
//
//  The one way a mastery mark is written or taken back (domain logic review
//  2026-11-20, R2). The Checklist (a cell and the selection bar), the
//  presentation sheet's pill and the sequence recap, the work page's offer and
//  Claude's `mark_mastered` all come through here, so they leave the same rows:
//
//  - Mark: every history row she has for the lesson becomes a mastery mark
//    (proficient, with a mastered day). Claude's tool used to mark only the
//    latest, the Checklist only the latest, the pill every row.
//  - Her open work on the lesson closes as Mastered (Danny, 2026-11-20). The
//    Checklist closed it as Finished, the pill and Claude left it open. No work
//    is made when she has none: the mark is what the grid reads. "Her work" is
//    the Checklist cell's (`closeOpenWork`).
//  - "Already mastered" means any row is a mastery mark, read one way
//    (`SequenceStanding.isMasteryMark`): `masteredAt` set or the proficient state.
//  - Unmark takes back the mastery rows only: her presentations, her other
//    history and her work (closed as Mastered or not) stay as they are.
//
//  A child with no history row for the lesson gets nothing here; the caller
//  decides whether that refuses (Claude) or attaches a presentation first (the
//  Checklist, the recap). Nothing saves; the caller owns the save.
//

import CoreData
import Foundation
import OSLog

@MainActor
enum MasteryMarking {
    private static let logger = Logger.lessons

    /// What one mark or unmark did, child by child.
    struct Outcome: Equatable {
        /// Children whose rows it changed: newly mastered, or no longer.
        var changed: [UUID] = []
        /// Children it left as they were: already mastered (for a mark, with the
        /// day of the earlier mark when one is recorded) or not mastered (for an unmark).
        var unchanged: [Unchanged] = []
        /// Children with no history row for the lesson; nothing was written for them.
        var unrecorded: [UUID] = []
        /// Work rows closed as Mastered.
        var closedWork = 0
    }

    struct Unchanged: Equatable {
        let studentID: UUID
        let masteredOn: Date?
    }

    // MARK: - Reading

    /// Her history rows for the lesson.
    static func rows(
        of studentID: UUID, lessonID: UUID, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@", studentID.uuidString, lessonID.uuidString
        )
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// Whether any of `rows` is a mastery mark.
    static func isMastered(_ rows: [CDLessonPresentation]) -> Bool {
        rows.contains(where: SequenceStanding.isMasteryMark)
    }

    // MARK: - Mark

    /// Marks each child mastered on the lesson, as of `day`. See the file header.
    @discardableResult
    static func mark(
        _ studentIDs: [UUID], lessonID: UUID, on day: Date = Date(), in context: NSManagedObjectContext
    ) -> Outcome {
        var outcome = Outcome()
        for studentID in unique(studentIDs) {
            let rows = rows(of: studentID, lessonID: lessonID, in: context)
            guard !rows.isEmpty else {
                outcome.unrecorded.append(studentID)
                continue
            }
            let marks = rows.filter(SequenceStanding.isMasteryMark)
            if marks.isEmpty {
                for row in rows { raise(row, masteredOn: day, observedOn: day) }
                outcome.changed.append(studentID)
            } else {
                // Already mastered: the marks keep their days (a mark carrying
                // only its day takes the state too), and any row that isn't one
                // takes the earlier mark's day.
                for row in marks where row.state != .proficient { row.state = .proficient }
                let masteredOn = marks.compactMap(\.masteredAt).min()
                for row in rows where !SequenceStanding.isMasteryMark(row) {
                    raise(row, masteredOn: masteredOn ?? day, observedOn: day)
                }
                outcome.unchanged.append(Unchanged(studentID: studentID, masteredOn: masteredOn))
            }
            outcome.closedWork += closeOpenWork(of: studentID, lessonID: lessonID, on: day, in: context)
        }
        return outcome
    }

    /// One row to a mastery mark. A row already marked keeps its day.
    private static func raise(_ row: CDLessonPresentation, masteredOn: Date, observedOn day: Date) {
        if row.state != .proficient { row.state = .proficient }
        if row.masteredAt == nil { row.masteredAt = masteredOn }
        if (row.lastObservedAt ?? .distantPast) < day { row.lastObservedAt = day }
    }

    // MARK: - Unmark

    /// Takes the mastery mark back for each child: only her mastery rows change,
    /// to Presented with no mastered day.
    @discardableResult
    static func unmark(_ studentIDs: [UUID], lessonID: UUID, in context: NSManagedObjectContext) -> Outcome {
        var outcome = Outcome()
        let now = Date()
        for studentID in unique(studentIDs) {
            let rows = rows(of: studentID, lessonID: lessonID, in: context)
            guard !rows.isEmpty else {
                outcome.unrecorded.append(studentID)
                continue
            }
            let marks = rows.filter(SequenceStanding.isMasteryMark)
            guard !marks.isEmpty else {
                outcome.unchanged.append(Unchanged(studentID: studentID, masteredOn: nil))
                continue
            }
            for row in marks {
                row.state = .presented
                row.masteredAt = nil
                row.lastObservedAt = now
            }
            outcome.changed.append(studentID)
        }
        return outcome
    }

    // MARK: - Her work

    /// Closes her open work on the lesson as Mastered and returns how many rows
    /// closed. Her work is what her Checklist cell shows: the rows she owns, or,
    /// when she owns none, the group rows that name her with no owner of their
    /// own (a classmate on one then reads Reviewing, as the grid always showed).
    /// A classmate's linked copy that names her is never hers. This is the one
    /// place the ownership rule is read here, so Phase 5's rule replaces it in
    /// one spot.
    private static func closeOpenWork(
        of studentID: UUID, lessonID: UUID, on day: Date, in context: NSManagedObjectContext
    ) -> Int {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "lessonID == %@", lessonID.uuidString), WorkStatus.openPredicate
        ])
        request.relationshipKeyPathsForPrefetching = ["participants"]
        let involving = context.safeFetch(request).filter {
            !$0.isDeleted && WorkGrouping.involves(studentID, in: $0)
        }
        let owned = involving.filter { WorkGrouping.owner(of: $0) == studentID }
        let open = owned.isEmpty ? involving.filter { WorkGrouping.owner(of: $0) == nil } : owned
        guard !open.isEmpty else { return 0 }
        do {
            try WorkLogService.log(
                open.map { .init(work: $0, status: .mastered) }, on: day, context: context, saveImmediately: false
            )
            return open.count
        } catch {
            logger.warning("Couldn't close work for a mastery mark: \(error)")
            return 0
        }
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
