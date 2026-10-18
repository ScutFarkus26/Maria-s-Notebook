//
//  ReadyForNextEngine.swift
//  Cosmic Daybook
//
//  Who is waiting on a next lesson, and how ready each child is.
//
//  At capture the guide can tag a child "ready for the next lesson", and a
//  mastery mark says the same thing more strongly. This turns both marks into
//  a queue: every child confirmed or mastered on a lesson whose successor in
//  the same sub-area is neither on her record nor on a plan for her.
//
//  It reads and proposes; it writes nothing. One rule decides how ready she
//  is, everywhere (Simplify the app, Phase 3, 2026-10-18; the rule itself is
//  `readiness(of:)` in `ReadyForNextEngine+PreviousLesson.swift`):
//  - Ready: the previous lesson is confirmed or mastered, no work from it is
//    open, and its last check-in didn't ask for more practice.
//  - Ready, check first: confirmed or mastered, but work from it is still
//    open, the last check-in asked for more practice, or the last recall check
//    came back shaky (or forgotten). Each comes with a plain reason.
//  - Not ready yet: the previous lesson isn't confirmed or mastered. Such a
//    child is never in the queue.
//  Confirmation is not mastery, and nothing here infers or writes a mastery
//  mark. Today, the Groups page, the sequence ladder and the Checklist's
//  Ready to Present lens all read this rule, so they cannot disagree about
//  the same child on the same day.
//
//  Cost is one `PresentationRecordIndex`, one next-lesson cache, one fetch of
//  the work on the lessons the children were confirmed on (two when a row
//  names more than one child) and one of their recall checks: nothing per
//  candidate.
//

import CoreData
import Foundation

/// How ready a child is for the next lesson in a sequence.
nonisolated enum ReadinessTier: String, Sendable, CaseIterable {
    /// Ready: nothing about the previous lesson needs a look first.
    case ready
    /// Ready, check first: the previous lesson is confirmed, but something
    /// about it (open work, practice asked for, a shaky recall) is worth a
    /// look before going on. The raw value predates the name and is kept: the
    /// `students_ready` tool's `include_almost_ready` filter reads this case.
    case almostReady
    /// Not ready yet: the previous lesson isn't confirmed or mastered. Never
    /// in the queue; the Checklist reads it for a cell.
    case notReady

    /// "Ready", "Ready, check first", "Not ready yet".
    var title: String {
        switch self {
        case .ready: "Ready"
        case .almostReady: "Ready, check first"
        case .notReady: "Not ready yet"
        }
    }
}

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
    /// `.ready` or `.almostReady` (Ready, check first); a child who is not
    /// ready is simply not here.
    let tier: ReadinessTier
    /// Plain sentences for the guide, empty when she is ready.
    let reasons: [String]
    /// The latest day the evidence lesson was given to her.
    let basisDate: Date?
    /// Where she stands on the evidence lesson, for a row to show before the
    /// guide gives the next one.
    let previous: PreviousLessonStatus
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
    ///   - context: for the work and recall checks on the evidence lessons.
    @MainActor
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

        var candidates: [Candidate] = []
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
                candidates.append(Candidate(
                    studentID: studentID, lessonID: lessonID, nextLessonID: nextID, detail: detail
                ))
            }
        }
        guard !candidates.isEmpty else { return [] }

        let record = PreviousLessonRecord(
            pairs: candidates.map { PreviousLessonRecord.Pair(studentID: $0.studentID, lessonID: $0.lessonID) },
            in: context
        )
        let items = candidates.map { candidate in
            let previous = record.status(
                student: candidate.studentID, lesson: candidate.lessonID, given: candidate.detail
            )
            let verdict = readiness(of: previous)
            return ReadyForNextItem(
                studentID: candidate.studentID,
                lessonID: candidate.lessonID,
                nextLessonID: candidate.nextLessonID,
                basis: candidate.detail.mastered ? .mastered : .confirmed,
                tier: verdict.tier,
                reasons: verdict.reasons,
                basisDate: candidate.detail.days.last,
                previous: previous
            )
        }
        // A dictionary walk has no order of its own; the callers want the same
        // queue twice running.
        return items.sorted { $0.id < $1.id }
    }

    /// A child confirmed or mastered on a lesson whose successor is waiting.
    private struct Candidate {
        let studentID: String
        let lessonID: String
        let nextLessonID: String
        let detail: PresentationRecordIndex.Given
    }
}
