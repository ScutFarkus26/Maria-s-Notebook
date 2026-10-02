// PresentationRecorder.swift
// Record: the children who weren't there stay on the plan, and the rest get
// the presentation.
//
// Shared by the presentation sheet's Record button and the Ready row's
// one-click Presented, so both take an absent child off the same way: onto a
// plan of her own for the same lesson (an existing On Deck plan for exactly
// those children is reused), with her promoted year-plan entry following her.

import CoreData
import Foundation

enum PresentationRecorder {
    struct Result {
        let undoToken: ImmediatePresentationRecordingService.UndoToken
        /// Children moved to a plan of their own because they weren't there.
        let keptOnPlan: [UUID]
    }

    enum RecordError: LocalizedError {
        case nobodyPresent
        case missingLesson
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .nobodyPresent:
                return "Choose at least one child who was there before recording this presentation."
            case .missingLesson:
                return "Choose the lesson before recording this presentation."
            case .saveFailed(let message):
                return message
            }
        }
    }

    /// Children on the plan whom attendance marks absent on `day`.
    static func absentStudentIDs(
        on day: Date,
        among studentIDs: Set<UUID>,
        context: NSManagedObjectContext
    ) -> Set<UUID> {
        let statuses = context.attendanceStatuses(for: Array(studentIDs), on: day)
        return Set(statuses.compactMap { $0.value == .absent ? $0.key : nil })
    }

    static func record(
        _ assignment: CDLessonAssignment,
        presentIDs: Set<UUID>,
        on day: Date,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> Result {
        guard let lesson = assignment.lesson else { throw RecordError.missingLesson }
        let planned = assignment.resolvedStudentIDs
        let present = planned.filter(presentIDs.contains)
        guard !present.isEmpty else { throw RecordError.nobodyPresent }
        let absent = planned.filter { !presentIDs.contains($0) }

        if !absent.isEmpty {
            keepOnPlan(Set(absent), takenOffOf: assignment, lesson: lesson, keeping: present, context: context)
            guard saveCoordinator.save(context, reason: "Keeping absent children on the plan") else {
                throw RecordError.saveFailed(
                    saveCoordinator.lastSaveErrorMessage ?? "The children who weren't there could not be moved."
                )
            }
            PresentationDetailUtilities.notifyInboxRefresh()
        }

        let token = try ImmediatePresentationRecordingService.record(
            assignment: assignment,
            presentedOn: day,
            context: context,
            saveCoordinator: saveCoordinator
        )
        return Result(undoToken: token, keptOnPlan: absent)
    }

    /// Takes `absent` off `assignment` onto a plan of their own and returns
    /// that plan (inserted, or an existing unscheduled one reused). Does not
    /// save. Also used by Today's "Move them to tomorrow"
    /// (`TodayAbsentMover`).
    @discardableResult
    static func keepOnPlan(
        _ absent: Set<UUID>,
        takenOffOf assignment: CDLessonAssignment,
        lesson: CDLesson,
        keeping present: [UUID],
        context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        // Their year-plan entries go back to planned first, so the plan they
        // land on can pick them up.
        PresentationRecordCleanup.removeStudents(
            Set(absent.map(\.uuidString)), from: assignment, in: context
        )
        assignment.studentIDs = present.map(\.uuidString)
        assignment.modifiedAt = Date()

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", assignment.lessonID)
        let existing = context.safeFetch(request).first {
            $0 !== assignment && !$0.isDeleted && !$0.isPresented
                && $0.scheduledFor == nil && Set($0.resolvedStudentIDs) == absent
        }
        let plan: CDLessonAssignment
        if let existing {
            plan = existing
        } else {
            let studentRequest = CDFetchRequest(CDStudent.self)
            studentRequest.predicate = NSPredicate(format: "id IN %@", Array(absent))
            let students = context.safeFetch(studentRequest)
            plan = PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
        }
        YearPlanPromotionService.promoteMatchingEntries(into: plan, context: context)
        return plan
    }
}
