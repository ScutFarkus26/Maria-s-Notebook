//
//  MCPNotebookTools+RepeatGuard.swift
//  Cosmic Daybook
//
//  Giving a lesson twice is a teaching decision, not a filing accident.
//
//  A guide re-presents for two reasons: the child did not take it the first
//  time (a second pass), or the work has come round again and she is revisiting
//  it deliberately (a review). Until now both landed in the notebook exactly
//  like a bookkeeping slip — a second row for a lesson already on record, with
//  nothing to say which it was. `schedule_presentation` and
//  `record_presentation` therefore refuse a lesson a named child already has on
//  record and name the days she had it, unless the caller says which of the two
//  this is with `purpose`.
//
//  Saying so is not just a password past the guard. `second_pass` flags the
//  child's previous record `needsAnotherPresentation`, the same bit the recall
//  queue and the capture review's "re-present" decision set, so the planning
//  reads that already look for it see the re-teach. Both purposes write a note
//  line on the new record, which `student_presentation_history` reads back as
//  "(2nd time; second pass)".
//
//  The record itself is read through PresentationRecordIndex, so "already has
//  it" means exactly what it means everywhere else in the app.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Why a Lesson Is Being Given Again

    /// The two reasons a guide gives a lesson a child already has.
    enum RepeatPurpose: String, CaseIterable, Sendable {
        /// She did not take it the first time; the earlier record is flagged
        /// for re-teaching.
        case secondPass = "second_pass"
        /// A deliberate revisit of work already on record.
        case review

        /// How the purpose opens its note line, and reads in a receipt when
        /// lowercased.
        var displayName: String {
            switch self {
            case .secondPass: return "Second pass"
            case .review: return "Review"
            }
        }

        /// `"Second pass — planned 2026-09-10"` — the first line of the new
        /// record's notes, so the reason survives in the notebook itself and
        /// not only in the conversation that made it.
        func noteLine(plannedOn day: Date) -> String {
            "\(displayName) — planned \(MCPNotebookTools.dayString(day))"
        }

        /// Reads the purpose back off a record's notes. Only the first line
        /// counts: anything the guide typed underneath is their own text.
        static func parse(notes: String) -> RepeatPurpose? {
            let first = notes.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)?.trimmed() ?? ""
            return allCases.first { first.hasPrefix("\($0.displayName) —") }
        }

        /// The optional `purpose` argument. Absent or empty is nil — the guard
        /// then does the refusing; anything else throws rather than being
        /// quietly read as "no purpose", which would file a repeat unmarked.
        static func argument(
            _ arguments: [String: JSONValue], _ key: String = "purpose"
        ) throws -> RepeatPurpose? {
            guard let raw = MCPNotebookTools.nonEmpty(arguments[key]?.stringValue) else { return nil }
            guard let purpose = RepeatPurpose(rawValue: raw) else {
                let allowed = allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
                throw MCPToolError("\(key) must be \(allowed), not \"\(raw)\".")
            }
            return purpose
        }
    }

    /// The `purpose` property both tools expose, so the two schemas describe
    /// the same argument in the same words.
    static let repeatPurposeProperty: JSONValue = [
        "type": "string",
        "enum": .array(RepeatPurpose.allCases.map { .string($0.rawValue) }),
        "description": .string("Required only when a named child already has this lesson on record: "
            + "second_pass (she needs it again — her previous record is flagged for re-teaching) or "
            + "review (a deliberate revisit). Either way the reason is written on the new record.")
    ]

    // MARK: - Who Already Has It

    /// One child the record already covers for this lesson, with the days it
    /// says so. Empty days mean an undated "previously presented" mark.
    struct RepeatConflict {
        let student: CDStudent
        let days: [Date]
    }

    /// The named children the record already covers for this lesson.
    ///
    /// A day on or after `day` is not a conflict: the same lesson, children and
    /// day is an edit of the record that is already there, which is what
    /// `record_presentation` does with it. An undated mark conflicts too — the
    /// record says she has had it, it just cannot say when.
    static func repeatConflicts(
        lessonID: String, students: [CDStudent], before day: Date, index: PresentationRecordIndex
    ) -> [RepeatConflict] {
        let boundary = AppCalendar.startOfDay(day)
        return students.compactMap { student in
            guard let studentID = student.id?.uuidString,
                  let given = index.given(student: studentID, lesson: lessonID)
            else { return nil }
            guard !given.days.isEmpty else { return RepeatConflict(student: student, days: []) }
            let earlier = given.days.filter { $0 < boundary }
            return earlier.isEmpty ? nil : RepeatConflict(student: student, days: earlier)
        }
    }

    // MARK: - Refusing

    /// One tool call's worth of conflicts for a single lesson.
    struct RepeatRefusal {
        let lesson: CDLesson
        let conflicts: [RepeatConflict]
        /// How many children the call named for that lesson.
        let total: Int
    }

    static func refuseRepeat(
        tool: String, lesson: CDLesson, conflicts: [RepeatConflict], of total: Int
    ) -> MCPToolError {
        refuseRepeat(tool: tool, [RepeatRefusal(lesson: lesson, conflicts: conflicts, total: total)])
    }

    /// The refusal, in the confirm-on-first-call voice `discard_presentation`
    /// uses: what was not done, who already has it and when, and the two words
    /// that let the call through.
    static func refuseRepeat(tool: String, _ refusals: [RepeatRefusal]) -> MCPToolError {
        let found = refusals.map(sentence(for:)).joined(separator: " ")
        return MCPToolError(
            "\(tool) refused — nothing has been changed. \(found) "
                + "Re-call with purpose: \"second_pass\" (she needs it again) or purpose: \"review\" "
                + "(a deliberate revisit). student_presentation_history with lesson has the detail."
        )
    }

    private static func sentence(for refusal: RepeatRefusal) -> String {
        let name = "\"\(refusal.lesson.name)\""
        if refusal.total == 1, let only = refusal.conflicts.first {
            return "\(only.student.fullName) already has \(name) on record (\(daysText(only.days)))."
        }
        let detail = refusal.conflicts
            .map { "\($0.student.fullName) (\(daysText($0.days)))" }
            .joined(separator: ", ")
        let verb = refusal.conflicts.count == 1 ? "has" : "have"
        return "\(refusal.conflicts.count) of these \(refusal.total) already \(verb) "
            + "\(name) on record: \(detail)."
    }

    private static func daysText(_ days: [Date]) -> String {
        days.isEmpty ? "undated" : days.map { dayString($0) }.joined(separator: ", ")
    }

    // MARK: - Writing the Reason Down

    /// What a call decided about a repeat: the purpose it gave, who it turned
    /// out to be a repeat for, and the record it read to find out.
    struct RepeatIntent {
        let purpose: RepeatPurpose
        let conflicts: [RepeatConflict]
        let lessonID: String
        let index: PresentationRecordIndex
    }

    /// Records why the lesson is being given again: a second pass flags each
    /// conflicting child's most recent record for re-teaching — the same bit
    /// the recall queue and the capture review's "re-present" set — and either
    /// purpose opens the new record's notes with its line.
    ///
    /// Idempotent on the note: a record that already opens with a purpose line
    /// keeps the one it has, so re-filing the same account does not stack them.
    static func recordRepeatIntent(
        _ intent: RepeatIntent,
        draft: CDLessonAssignment,
        plannedOn day: Date,
        in context: NSManagedObjectContext
    ) {
        let purpose = intent.purpose
        if purpose == .secondPass {
            let latest = intent.index.latestPresentedAssignmentByLesson[intent.lessonID] ?? [:]
            for conflict in intent.conflicts {
                guard let studentID = conflict.student.id?.uuidString,
                      let objectID = latest[studentID],
                      let prior = context.existing(CDLessonAssignment.self, objectID)
                else { continue }
                prior.needsAnotherPresentation = true
                prior.modifiedAt = Date()
            }
        }

        guard RepeatPurpose.parse(notes: draft.notes) == nil else { return }
        let existing = draft.notes.trimmed()
        let line = purpose.noteLine(plannedOn: day)
        draft.notes = existing.isEmpty ? line : "\(line)\n\(existing)"
        draft.modifiedAt = Date()
    }

    /// The receipt's tail, so a caller who passed `purpose` can see what the
    /// record actually said — including "nobody had it before", which usually
    /// means the purpose was not needed at all.
    static func repeatReceipt(_ purpose: RepeatPurpose?, conflicts: Int, of total: Int) -> String {
        guard let purpose else { return "" }
        guard conflicts > 0 else { return " (nobody had it before; purpose noted)" }
        return " — \(conflicts) of \(total) already had it (\(purpose.displayName.lowercased()) noted)"
    }

    // MARK: - Reading the Reason Back

    /// "2nd", for the ordinal a history row carries when a child has had one
    /// lesson more than once.
    static func ordinalText(_ value: Int) -> String {
        let suffix: String
        switch (value % 10, value % 100) {
        case (1, 11), (2, 12), (3, 13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }
}
