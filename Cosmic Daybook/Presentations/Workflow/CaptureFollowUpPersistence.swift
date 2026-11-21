//
//  CaptureFollowUpPersistence.swift
//  Cosmic Daybook
//
//  The per-student outcomes a guide confirms after a presentation — offer
//  practice, set follow-up work, re-present, ready for the next lesson, or
//  keep observing — written the one way the app writes them. The command
//  bar's capture review and the MCP `record_presentation` tool both come
//  through here, so a decision filed from Claude Desktop lands in the same
//  rows the in-app review would have written.
//
//  That includes her follow-up row on the presentation (domain logic review
//  2026-11-20, R6): Ready resolves it, Re-present resolves it as support,
//  Practice and Follow-up work leave it open as work to check, and Keep
//  watching leaves it open to watch. Only the sheet wrote it, so a child
//  Claude or the command bar filed as Ready stayed in Keep Watching. No
//  decision (`.none`) leaves the row as it is.
//

import CoreData
import Foundation

enum CaptureFollowUpPersistence {
    /// One child's outcome from a reviewed presentation.
    struct Entry {
        let studentID: UUID
        let observation: String
        let followUp: CaptureFollowUp
        let followUpDetail: String
    }

    /// Applies every entry's outcome against the recorded presentation and
    /// returns how many work items were created. Nothing here saves; the
    /// caller owns the save so the whole review lands or none of it does.
    /// - Parameter reviewAt: when the work to check comes due, for Practice and
    ///   Follow-up work; nil leaves it undated.
    @discardableResult
    static func persist(
        _ entries: [Entry],
        assignment: CDLessonAssignment,
        lesson: CDLesson,
        persistence: CapturePersistenceContext,
        reviewAt: Date? = nil,
        now: Date = Date()
    ) throws -> Int {
        let rows = PresentationFollowUpService.rows(for: persistence.presentationID, in: persistence.context)
        var workCount = 0
        for entry in entries {
            if try apply(entry, assignment: assignment, lesson: lesson, persistence: persistence) {
                workCount += 1
            }
            guard entry.followUp != .none,
                  let row = rows.first(where: { UUID(uuidString: $0.studentID) == entry.studentID })
            else { continue }
            writeFollowUpRow(entry.followUp, to: row, reviewAt: reviewAt, now: now)
        }
        return workCount
    }

    /// One entry's records, apart from her follow-up row. True when it made work.
    private static func apply(
        _ entry: Entry, assignment: CDLessonAssignment, lesson: CDLesson, persistence: CapturePersistenceContext
    ) throws -> Bool {
        switch entry.followUp {
        case .none:
            return false
        case .continueObserving:
            // With no note, the open follow-up row is the reminder.
            if !entry.observation.trimmed().isEmpty {
                markObservationForFollowUp(entry: entry, assignment: assignment, context: persistence.context)
            }
            return false
        case .practice:
            return try createWorkIfNeeded(kind: .practiceLesson, entry: entry, persistence: persistence)
        case .followUpWork:
            return try createWorkIfNeeded(kind: .followUpAssignment, entry: entry, persistence: persistence)
        case .represent:
            // The record she has is the one that did not take: filed the
            // way a meeting's or a recall check's Re-present files it, so
            // the planning reads see the second pass and not just a new
            // draft. The shared flag only when she had it alone; in a group
            // her own row says it, or one child's Re-present read as the
            // whole group's (bug hunt 2026-10-12, #45).
            try MeetingLessonDecisions.flagForAnotherPresentation(
                assignment, studentID: entry.studentID, context: persistence.context
            )
            try createRepresentationIfNeeded(
                studentID: entry.studentID, lesson: lesson, context: persistence.context
            )
            return false
        case .readyForNextLesson:
            assignment.confirmStudent(entry.studentID)
            return false
        }
    }

    /// One child's decision on her follow-up row for the presentation: work to
    /// check stays open with its date, a re-presentation or a next lesson
    /// resolves it, and keep watching leaves it open to watch. Shared with the
    /// sheet, which also re-dates an unchanged work-giving decision.
    static func writeFollowUpRow(
        _ decision: CaptureFollowUp, to row: CDLessonPresentation, reviewAt: Date?, now: Date
    ) {
        if row.followUpActionRaw == nil {
            PresentationFollowUpService.beginFollowing(row, at: now)
        }
        switch decision {
        case .practice, .followUpWork:
            PresentationFollowUpService.reopen(row, at: now)
            PresentationFollowUpService.setAction(.checkWork, for: [row], reviewAt: reviewAt, now: now)
        case .represent:
            PresentationFollowUpService.resolve(.supportOrRepresent, row: row, at: now)
        case .readyForNextLesson:
            PresentationFollowUpService.resolve(.readyForNextPresentation, row: row, at: now)
        case .continueObserving, .none:
            PresentationFollowUpService.reopen(row, at: now)
            PresentationFollowUpService.setAction(.watchWork, for: [row], now: now)
        }
    }

    /// Creates the practice or follow-up work item once per (presentation,
    /// child, kind); a second review of the same presentation finds the
    /// existing item and leaves it alone.
    static func createWorkIfNeeded(
        kind: WorkKind,
        entry: Entry,
        persistence: CapturePersistenceContext
    ) throws -> Bool {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND studentID == %@ AND kindRaw == %@",
            persistence.presentationID.uuidString,
            entry.studentID.uuidString,
            kind.rawValue
        )
        request.fetchLimit = 1
        guard try persistence.context.fetch(request).isEmpty else { return false }

        let defaultTitle = kind == .practiceLesson
            ? "Practice: \(persistence.lessonName)"
            : "Follow up: \(persistence.lessonName)"
        let detail = entry.followUpDetail.trimmed()
        _ = try WorkRepository(context: persistence.context).createWork(
            studentID: entry.studentID,
            lessonID: persistence.lessonID,
            title: detail.isEmpty ? defaultTitle : detail,
            kind: kind,
            presentationID: persistence.presentationID,
            saveImmediately: false
        )
        return true
    }

    /// Puts the lesson back on the planning list for one child, unless a plan
    /// naming her is already waiting.
    static func createRepresentationIfNeeded(
        studentID: UUID,
        lesson: CDLesson,
        context: NSManagedObjectContext
    ) throws {
        guard let lessonID = lesson.id else { return }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let alreadyPlanned = try context.fetch(request).contains {
            !$0.isPresented && $0.resolvedStudentIDs.contains(studentID)
        }
        guard !alreadyPlanned else { return }

        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
        studentRequest.fetchLimit = 1
        guard let student = try context.fetch(studentRequest).first else { return }
        let draft = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        // Says on the draft itself why the lesson is coming round again, in the
        // words student_presentation_history reads back.
        draft.notes = MCPNotebookTools.RepeatPurpose.secondPass.noteLine(plannedOn: Date())
    }

    /// Flags the child's observation on this presentation for the follow-up
    /// inbox, writing the note if the relationship has not caught up yet.
    ///
    /// Two observations for one child in one filing are written as one note,
    /// the entries joined by a blank line (`record_presentation`), so an
    /// entry's text is matched against each joined piece as well as the whole;
    /// matching the whole only wrote a second, flagged copy (bug hunt
    /// 2026-10-12, #51). A piece must match exactly: "Yes." found anywhere
    /// inside a longer note flagged the wrong one.
    static func markObservationForFollowUp(
        entry: Entry,
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) {
        let body = entry.observation.trimmed()
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        let hers = notes.filter { !$0.isDeleted && $0.scope == .student(entry.studentID) }
        if let note = hers.first(where: { $0.body.trimmed() == body })
            ?? hers.first(where: { note in
                !body.isEmpty && note.body.components(separatedBy: "\n\n").contains { $0.trimmed() == body }
            }) {
            note.needsFollowUp = true
            note.updatedAt = Date()
            return
        }

        // This normally only occurs while the relationship has not refreshed.
        let note = CDNote(context: context)
        note.body = body
        note.scope = .student(entry.studentID)
        note.lessonID = assignment.lessonID
        note.lessonAssignment = assignment
        note.needsFollowUp = true
        note.syncStudentLinks(in: context)
    }
}
