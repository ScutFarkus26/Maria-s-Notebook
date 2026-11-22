//
//  ReadyGroups+OneLesson.swift
//  Cosmic Daybook
//
//  Who is ready for one lesson, without building every card.
//
//  The present-a-lesson picker lists the children ready for the lesson on
//  screen. Building the whole queue for a popover would read the whole record
//  and every child's work; this reads only the lesson and the one before it,
//  and only the work of children with a mark on that previous lesson. The
//  rules are not copied: it runs the same `ReadyForNextEngine` the cards fold,
//  over a record scoped to those lessons, and keeps what a card would count
//  as Ready, so the picker and the Groups page cannot disagree.
//

import CoreData
import Foundation

nonisolated extension ReadyGroups {

    /// The children in `studentIDs` that `build` would list as Ready on
    /// `lessonID`'s card: given the lesson before it in its sub-area (and
    /// confirmed or mastered on it, when that lesson requires confirmation),
    /// neither given nor planned this one, and Ready rather than Ready, check
    /// first (`ReadyForNextEngine.readiness(of:)`).
    ///
    /// - Parameters:
    ///   - lessonID: the lesson being planned, as a UUID string.
    ///   - studentIDs: the children to consider, as UUID strings. The caller
    ///     chooses them as it would a snapshot's roster (enrolled, test
    ///     students hidden).
    ///   - lessons: the whole lesson library; "before" is read from it.
    ///   - context: for the record, and the work and recall checks the rule reads.
    @MainActor
    static func readyStudentIDs(
        for lessonID: String,
        among studentIDs: Set<String>,
        lessons: [CDLesson],
        in context: NSManagedObjectContext
    ) -> Set<String> {
        readiness(for: lessonID, among: studentIDs, lessons: lessons, in: context).ready
    }

    /// Who a card would list for one lesson: Ready, and Ready, check first
    /// with what to check ("2 pieces of work still open"). The picker shows
    /// both in its Ready run, so a child the rules hold back says why
    /// instead of dropping silently to Everyone Else.
    struct OneLessonReadiness: Equatable {
        var ready: Set<String> = []
        /// Student id → the reasons, joined as a card joins them.
        var checkFirst: [String: String] = [:]
    }

    /// `readyStudentIDs`, with the Ready, check first children as well.
    @MainActor
    static func readiness(
        for lessonID: String,
        among studentIDs: Set<String>,
        lessons: [CDLesson],
        in context: NSManagedObjectContext
    ) -> OneLessonReadiness {
        guard !studentIDs.isEmpty,
              LessonSequenceOrder(lessons: lessons).position(of: lessonID) != nil else { return OneLessonReadiness() }
        // Every lesson whose next is this one: normally one, but two lessons
        // filed at the same step would both lead here, as they do in the queue.
        let previous = Set(BlockingAlgorithmEngine.buildNextLessonCache(lessons).compactMap { key, next in
            next.id?.uuidString == lessonID ? key.uuidString : nil
        })
        guard !previous.isEmpty else { return OneLessonReadiness() }

        let index = PresentationRecordIndex(
            lessonIDs: previous.union([lessonID]), students: studentIDs, in: context
        )
        // Only a child given the previous lesson can be in the queue for this
        // one, so only her work and recall checks are read. Whether she needs
        // a mark on it is the lesson's own setting, which the engine reads.
        let marked = studentIDs.filter { studentID in
            previous.contains { index.given(student: studentID, lesson: $0) != nil }
        }
        guard !marked.isEmpty else { return OneLessonReadiness() }

        let items = ReadyForNextEngine.items(
            studentIDs: Array(marked), lessons: lessons, index: index, in: context
        )
        var result = OneLessonReadiness()
        for item in items where item.nextLessonID == lessonID {
            switch item.tier {
            case .ready: result.ready.insert(item.studentID)
            case .almostReady: result.checkFirst[item.studentID] = item.reasons.joined(separator: "; ")
            case .notReady: break
            }
        }
        return result
    }
}
