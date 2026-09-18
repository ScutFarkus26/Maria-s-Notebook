//
//  ReadyForNextEngine.swift
//  Cosmic Daybook
//
//  Who is waiting on a next lesson.
//
//  At capture the guide can tag a child "ready for the next lesson", and a
//  mastery mark says the same thing more strongly — but until now neither
//  went anywhere. The tag sat on the presentation it was made from, and the
//  only way to say "soon" was to put a date on it. This turns both marks into
//  a queue: every child confirmed or mastered on a lesson whose successor in
//  the same sub-area is neither on her record nor on a plan for her.
//
//  It reads and proposes; it writes nothing. The practice gate is the one
//  the Small Sequence Planner applies — a sub-area that requires practice
//  holds a child at "almost ready" while her own work on the lesson she just
//  had is still open — so the two surfaces do not disagree about the same
//  child on the same day.
//
//  Cost is one `PresentationRecordIndex`, one work fetch, one next-lesson
//  cache and dictionary lookups from there: nothing per candidate.
//

import CoreData
import Foundation

/// One child, one lesson she is ready for, and why.
nonisolated struct ReadyForNextItem: Sendable, Hashable, Identifiable {

    /// What puts her in the queue. Mastery is the stronger mark, so it wins
    /// when the record holds both.
    enum Basis: String, Sendable, Hashable {
        case confirmed
        case mastered
    }

    var id: String { "\(studentID)|\(nextLessonID)" }

    let studentID: String
    /// The lesson she was confirmed or mastered on — the queue's evidence.
    let lessonID: String
    /// The lesson she is ready for: the next in the same sub-area.
    let nextLessonID: String
    let basis: Basis
    /// `.ready` or `.almostReady`; a child who is not ready is simply not here.
    let tier: ReadinessTier
    /// Plain sentences for the guide, empty when she is ready.
    let reasons: [String]
    /// The latest day the evidence lesson was given to her.
    let basisDate: Date?
}

/// Builds the ready queue from a record that has already been read.
nonisolated enum ReadyForNextEngine {

    /// Every child in `studentIDs` who is confirmed or mastered on a lesson
    /// whose successor she has neither had nor been planned for.
    ///
    /// - Parameters:
    ///   - studentIDs: the children to consider, as UUID strings. The caller
    ///     decides who is in the universe — the tool passes the enrolled
    ///     roster, so a withdrawn child never surfaces.
    ///   - lessons: the whole lesson library; "next" is read from it.
    ///   - index: the record, built over at least these children.
    ///   - context: for the progression rules and the practice work.
    static func items(
        studentIDs: [String],
        lessons: [CDLesson],
        index: PresentationRecordIndex,
        in context: NSManagedObjectContext
    ) -> [ReadyForNextItem] {
        guard !studentIDs.isEmpty, !lessons.isEmpty else { return [] }

        let nextCache = BlockingAlgorithmEngine.buildNextLessonCache(lessons)
        guard !nextCache.isEmpty else { return [] }
        var lessonsByID: [String: CDLesson] = [:]
        for lesson in lessons {
            if let id = lesson.id { lessonsByID[id.uuidString] = lesson }
        }
        let practice = PracticeRecord(studentIDs: Set(studentIDs), in: context)
        var requiresPracticeByLesson: [String: Bool] = [:]

        var items: [ReadyForNextItem] = []
        for studentID in Set(studentIDs) {
            for (lessonID, detail) in index.givenByStudent[studentID] ?? [:] {
                guard detail.confirmed || detail.mastered else { continue }
                guard let lesson = lessonsByID[lessonID],
                      let lessonUUID = lesson.id,
                      let next = nextCache[lessonUUID],
                      let nextID = next.id?.uuidString else { continue }
                // The record wins over the queue: a successor she has already
                // had, or one already on a plan for her, is not waiting.
                guard index.given(student: studentID, lesson: nextID) == nil,
                      !index.hasOpenPlan(student: studentID, lesson: nextID) else { continue }

                let gated = requiresPractice(
                    on: lesson, cache: &requiresPracticeByLesson, in: context
                ) && practice.isIncomplete(student: studentID, lesson: lessonID)
                let reasons: [String] = gated
                    ? ["practice on \(lesson.name) not yet complete"]
                    : []
                items.append(ReadyForNextItem(
                    studentID: studentID,
                    lessonID: lessonID,
                    nextLessonID: nextID,
                    basis: detail.mastered ? .mastered : .confirmed,
                    tier: reasons.isEmpty ? .ready : .almostReady,
                    reasons: reasons,
                    basisDate: detail.days.last
                ))
            }
        }
        // A dictionary walk has no order of its own; the callers want the same
        // queue twice running.
        return items.sorted { $0.id < $1.id }
    }

    /// The sub-area's practice rule, resolved once per lesson rather than
    /// once per candidate — `resolve` fetches the sequence settings.
    private static func requiresPractice(
        on lesson: CDLesson, cache: inout [String: Bool], in context: NSManagedObjectContext
    ) -> Bool {
        let key = lesson.id?.uuidString ?? lesson.name
        if let cached = cache[key] { return cached }
        let resolved = LessonProgressionRules.resolve(for: lesson, context: context).requiresPractice
        cache[key] = resolved
        return resolved
    }

    // MARK: - Practice

    /// Each child's own work, keyed by child and lesson, read in one fetch.
    private struct PracticeRecord {
        private let byStudentLesson: [String: [CDWorkModel]]

        init(studentIDs: Set<String>, in context: NSManagedObjectContext) {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "studentID IN %@", Array(studentIDs))
            var grouped: [String: [CDWorkModel]] = [:]
            for work in context.safeFetch(request) where !work.isDeleted {
                grouped[Self.key(work.studentID, work.lessonID), default: []].append(work)
            }
            byStudentLesson = grouped
        }

        private static func key(_ studentID: String, _ lessonID: String) -> String {
            studentID + "|" + lessonID
        }

        /// True when she has work on file for the lesson and some of it is
        /// still open.
        ///
        /// No work at all is deliberately *not* incomplete practice: it is
        /// practice the guide has not assigned yet, and holding every child
        /// at "almost ready" for a row nobody created would empty the queue.
        /// Only her own work gates her — a classmate's unfinished sheet on a
        /// shared piece of work must not hold her back, which is why the
        /// completeness test is asked per student.
        func isIncomplete(student studentID: String, lesson lessonID: String) -> Bool {
            guard let rows = byStudentLesson[Self.key(studentID, lessonID)], !rows.isEmpty,
                  let studentUUID = UUID(uuidString: studentID) else { return false }
            return rows.contains {
                !BlockingAlgorithmEngine.isWorkComplete(work: $0, requiredStudentIDs: [studentUUID])
            }
        }
    }
}
