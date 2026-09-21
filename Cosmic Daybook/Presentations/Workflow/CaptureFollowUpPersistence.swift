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
    @discardableResult
    static func persist(
        _ entries: [Entry],
        assignment: CDLessonAssignment,
        lesson: CDLesson,
        persistence: CapturePersistenceContext
    ) throws -> Int {
        var workCount = 0
        for entry in entries {
            switch entry.followUp {
            case .none:
                break
            case .continueObserving:
                markObservationForFollowUp(entry: entry, assignment: assignment, context: persistence.context)
            case .practice:
                if try createWorkIfNeeded(kind: .practiceLesson, entry: entry, persistence: persistence) {
                    workCount += 1
                }
            case .followUpWork:
                if try createWorkIfNeeded(kind: .followUpAssignment, entry: entry, persistence: persistence) {
                    workCount += 1
                }
            case .represent:
                // The record she has is the one that did not take: flag it for
                // re-teaching, the same bit the recall queue sets, so the
                // planning reads see the second pass and not just a new draft.
                assignment.needsAnotherPresentation = true
                assignment.modifiedAt = Date()
                try createRepresentationIfNeeded(
                    studentID: entry.studentID, lesson: lesson, context: persistence.context
                )
            case .readyForNextLesson:
                assignment.confirmStudent(entry.studentID)
            }
        }
        return workCount
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
    static func markObservationForFollowUp(
        entry: Entry,
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) {
        let body = entry.observation.trimmed()
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        if let note = notes.first(where: {
            $0.body.trimmed() == body && $0.scope == .student(entry.studentID)
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
