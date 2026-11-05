// StudentLessonRecords.swift
// One child's record on a sequence's lessons, read the way her track timeline reads it.

import CoreData
import Foundation

/// One child's record on a run of lessons, as her track timeline draws it
/// (`StudentAreaProgressionViewModel`). The Progress tab's track card reads the same for
/// its Next Lesson, which used to be the first lesson not mastered: a lesson she was
/// practicing showed as "Next Lesson" while the timeline marked a later one Next (bug
/// hunt 2026-11-03 #29).
///
/// What counts:
/// - her presentations, given and planned;
/// - the work that is hers by the Checklist's rule (`WorkVisibility`): the rows she owns,
///   and a shared row she is on (project work) though another child owns it, never a
///   classmate's linked copy naming her. Reading only the rows she owned left her shared
///   project work off the timeline while her Children card counted it (#26);
/// - her mastery marks, and where her year plan has her up to (`YearPlanNextLessons`):
///   that entry reads Planned, as on the Checklist (#28).
struct StudentLessonRecords {

    /// One lesson as the timeline draws it.
    struct LessonState {
        let status: LessonNodeStatus
        /// Her first presentation of the lesson that has been given, if any.
        let given: CDLessonAssignment?
        /// The work on the lesson that counts as hers.
        let work: [CDWorkModel]
        /// The first lesson with nothing for her yet: not given, planned, practiced or
        /// mastered. Plan Lesson is offered here.
        let isNext: Bool
    }

    /// Her presentations of the lessons, given and planned, in fetch order.
    let presentations: [CDLessonAssignment]
    /// lessonID → the work on it that counts as hers.
    let workByLesson: [String: [CDWorkModel]]
    let masteredLessonIDs: Set<String>
    /// The lessons whose year-plan entry is the one she's up to.
    let yearPlanNextLessonIDs: Set<String>

    /// - Parameters:
    ///   - lessonIDs: the sequence's lesson ids, in lesson order.
    ///   - presentations: the lessons' presentations, any roster, when the caller
    ///     already holds them; fetched otherwise.
    init(
        studentID: UUID,
        lessonIDs: [String],
        presentations: [CDLessonAssignment]? = nil,
        context: NSManagedObjectContext
    ) {
        let key = studentID.uuidString
        self.presentations = (presentations ?? Self.fetchPresentations(lessonIDs: lessonIDs, context: context))
            .filter { $0.studentIDs.contains(key) }
        let rows = Self.fetchWork(lessonIDs: lessonIDs, context: context)
        let visibility = WorkVisibility(rows: rows)
        workByLesson = Dictionary(grouping: rows.filter { visibility.isVisible($0, to: studentID) }, by: \.lessonID)
        masteredLessonIDs = Set(
            PresentationRecordIndex.masteryMarks(lessonIDs: Set(lessonIDs), in: context)
                .filter { $0.value.contains(key) }
                .keys
        )
        yearPlanNextLessonIDs = Set(
            YearPlanNextLessons.byLesson(sequences: [lessonIDs], students: [key], in: context).keys
        )
    }

    /// Each of `lessonIDs`' state, in the same order, by the Checklist's ladder
    /// (`LessonNodeStatus.resolve`).
    func states(lessonIDs: [String]) -> [LessonState] {
        var foundNext = false
        return lessonIDs.map { lessonID in
            // "Previously Presented" records are undated (state == .presented, presentedAt
            // == nil), so match on state as well: otherwise historical lessons show Not
            // Started and get suggested as next.
            let given = presentations.first {
                $0.lessonID == lessonID && ($0.isPresented || $0.presentedAt != nil)
            }
            // Planned and not yet given: on a day, or a draft waiting in the inbox.
            let planned = presentations.filter {
                $0.lessonID == lessonID && !$0.isPresented && $0.presentedAt == nil
            }
            let work = workByLesson[lessonID] ?? []
            let status = LessonNodeStatus.resolve(
                isPresented: given != nil,
                scheduledFor: planned.compactMap(\.scheduledFor).min(),
                isPlanned: !planned.isEmpty || yearPlanNextLessonIDs.contains(lessonID),
                isMastered: masteredLessonIDs.contains(lessonID),
                workStatuses: work.map(\.status)
            )
            let isNext = !foundNext && status == .notStarted
            if isNext { foundNext = true }
            return LessonState(status: status, given: given, work: work, isNext: isNext)
        }
    }

    // MARK: - Fetching

    /// Presentations of any of `lessonIDs`, matched the way `lessonIDUUID` links them
    /// (case-insensitively), in store order.
    private static func fetchPresentations(
        lessonIDs: [String], context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID IN[c] %@", lessonIDs)
        return context.safeFetch(request)
    }

    /// Every row of the lessons, open and closed, whoever owns it, with who is on
    /// it: a child's closed copy is what tells her classmate's open copy apart from
    /// a row she shares (`WorkVisibility`).
    private static func fetchWork(lessonIDs: [String], context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
