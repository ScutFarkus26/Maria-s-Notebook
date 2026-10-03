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
        /// Moving the absent children to a plan of their own didn't save.
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .nobodyPresent:
                return "Choose at least one child who was there before recording this presentation."
            case .missingLesson:
                return "Choose the lesson before recording this presentation."
            case .saveFailed:
                return "Couldn't keep the absent children on the plan. Nothing was recorded. Try again."
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

        var split: AbsentSplit?
        if !absent.isEmpty {
            var before = AbsentSplit(assignment, absent: Set(absent), context: context)
            let plan = keepOnPlan(
                Set(absent), takenOffOf: assignment, lesson: lesson, keeping: present, context: context
            )
            let madePlan = plan.isInserted ? plan : nil
            // The caller shows `RecordError.saveFailed`, so the global alert stays quiet.
            guard saveCoordinator.save(
                context, reason: "Keeping absent children on the plan", alertOnFailure: false
            ) else {
                throw RecordError.saveFailed
            }
            // Read after the save: an inserted plan carries a temporary id until then.
            before.createdPlanObjectID = madePlan?.objectID
            split = before
            PresentationDetailUtilities.notifyInboxRefresh()
        }

        do {
            var token = try ImmediatePresentationRecordingService.record(
                assignment: assignment,
                presentedOn: day,
                context: context,
                saveCoordinator: saveCoordinator
            )
            // Undo has to bring the absent children back too, whoever calls it.
            token.absentSplit = split
            return Result(undoToken: token, keptOnPlan: absent)
        } catch {
            // Nothing was recorded, so nobody should have been moved either.
            if let split {
                split.restore(onto: assignment, in: context)
                if saveCoordinator.save(
                    context, reason: "Putting absent children back on the plan", alertOnFailure: false
                ) {
                    PresentationDetailUtilities.notifyInboxRefresh()
                }
            }
            throw error
        }
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

    /// What taking the absent children off at Record changed, so Undo can put
    /// them back: the roster as it was, the plan made for them, and their
    /// year-plan entries for the lesson (pointed back at this presentation).
    struct AbsentSplit {
        let studentIDs: [String]
        let modifiedAt: Date?
        let absent: Set<UUID>
        let entries: [YearPlanReleasePreimage.Entry]
        /// The plan Record made for them; an existing plan it reused is left alone.
        var createdPlanObjectID: NSManagedObjectID?

        /// Reads the assignment before `keepOnPlan` runs.
        init(_ assignment: CDLessonAssignment, absent: Set<UUID>, context: NSManagedObjectContext) {
            studentIDs = assignment.studentIDs
            modifiedAt = assignment.modifiedAt
            self.absent = absent
            let request = CDFetchRequest(CDYearPlanEntry.self)
            request.predicate = NSPredicate(
                format: "lessonID == %@ AND studentID IN %@",
                assignment.lessonID, absent.map(\.uuidString)
            )
            entries = context.safeFetch(request).map {
                YearPlanReleasePreimage.Entry(
                    objectID: $0.objectID, statusRaw: $0.statusRaw, promotedAssignmentID: $0.promotedAssignmentID
                )
            }
        }

        /// Puts the roster back, removes the plan Record made for the absent
        /// children (unless it has since become something else) and restores
        /// their entries. Does not save.
        func restore(onto assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
            assignment.studentIDs = studentIDs
            assignment.modifiedAt = modifiedAt
            if let createdPlanObjectID,
               let plan = context.existing(CDLessonAssignment.self, createdPlanObjectID),
               !plan.isDeleted, !plan.isPresented, plan.scheduledFor == nil,
               Set(plan.resolvedStudentIDs) == absent {
                PresentationRecordCleanup.prepareToDelete(plan, in: context)
                context.delete(plan)
            }
            for entry in entries {
                guard let current = context.existing(CDYearPlanEntry.self, entry.objectID),
                      !current.isDeleted else { continue }
                current.statusRaw = entry.statusRaw
                current.promotedAssignmentID = entry.promotedAssignmentID
            }
        }
    }
}
