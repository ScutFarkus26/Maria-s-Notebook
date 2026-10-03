// TodayAbsentMover.swift
// "Move them to tomorrow": the children attendance marks absent come off the
// day's lessons and onto tomorrow.
//
// Each absent child goes the way Record sends one — `PresentationRecorder
// .keepOnPlan`, onto a plan of her own for the same lesson with her year-plan
// entry following her — and that plan is then scheduled for the day given.
// A lesson whose children are all absent simply moves whole. The present
// children stay on today's lesson.
//
// The guide asks for it (a row's menu or link, or once for the whole day in
// the Lessons header); nothing calls it on its own. Every lesson moves in one
// save, and the receipt takes all of it back for the toast's Undo.

import CoreData
import Foundation

enum TodayAbsentMover {

    /// Each description is shown as is in Today's toast.
    enum MoveError: LocalizedError {
        case saveFailed
        case undoSaveFailed
        case undoUnavailable

        var errorDescription: String? {
            switch self {
            case .saveFailed: return "Couldn't move the absent children. Nothing changed. Try again."
            case .undoSaveFailed: return "Couldn't undo the move. Try again."
            case .undoUnavailable: return "This move can no longer be undone."
            }
        }
    }

    /// What a move changed, enough to put it back.
    struct Receipt {
        /// The children moved, across every lesson.
        let movedStudentIDs: Set<UUID>
        /// The plans made for them; Undo deletes these.
        fileprivate let createdPlanIDs: [NSManagedObjectID]
        /// Today's lessons the children came off, with who was on each.
        fileprivate let rosters: [(objectID: NSManagedObjectID, studentIDs: [String])]
        /// Lessons that moved whole, and reused plans, as they were scheduled.
        fileprivate let schedules: [ScheduleSnapshot]
        /// The moved children's year-plan entries for these lessons.
        fileprivate let entries: [EntrySnapshot]
    }

    fileprivate struct ScheduleSnapshot {
        let objectID: NSManagedObjectID
        let stateRaw: String
        let scheduledFor: Date?
        let scheduledForDay: Date?

        init(_ assignment: CDLessonAssignment) {
            objectID = assignment.objectID
            stateRaw = assignment.stateRaw
            scheduledFor = assignment.scheduledFor
            scheduledForDay = assignment.scheduledForDay
        }
    }

    fileprivate struct EntrySnapshot {
        let objectID: NSManagedObjectID
        let statusRaw: String
        let promotedAssignmentID: String?

        init(_ entry: CDYearPlanEntry) {
            objectID = entry.objectID
            statusRaw = entry.statusRaw
            promotedAssignmentID = entry.promotedAssignmentID
        }
    }

    /// The absent children on a lesson that has not been given yet.
    static func absentChildren(on lesson: CDLessonAssignment, absent: Set<UUID>) -> Set<UUID> {
        guard !lesson.isPresented else { return [] }
        return Set(lesson.resolvedStudentIDs).intersection(absent)
    }

    /// Moves the absent children on `lessons` to `day`, in one save. Returns
    /// nil when none of them has an absent child.
    static func moveAbsent(
        from lessons: [CDLessonAssignment],
        absent: Set<UUID>,
        to day: Date,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> Receipt? {
        var moved = Set<UUID>()
        var created: [CDLessonAssignment] = []
        var rosters: [(objectID: NSManagedObjectID, studentIDs: [String])] = []
        var schedules: [ScheduleSnapshot] = []
        var entries: [EntrySnapshot] = []

        for assignment in lessons {
            let away = absentChildren(on: assignment, absent: absent)
            guard !away.isEmpty else { continue }
            let present = assignment.resolvedStudentIDs.filter { !away.contains($0) }
            if !present.isEmpty && assignment.lesson == nil { continue }
            entries += yearPlanEntries(lessonID: assignment.lessonID, studentIDs: away, context: context)
                .map(EntrySnapshot.init)
            moved.formUnion(away)

            guard let lesson = assignment.lesson, !present.isEmpty else {
                // Nobody is here for it: the lesson itself moves.
                schedules.append(ScheduleSnapshot(assignment))
                assignment.schedule(onDay: day)
                continue
            }
            rosters.append((assignment.objectID, assignment.studentIDs))
            let plan = PresentationRecorder.keepOnPlan(
                away, takenOffOf: assignment, lesson: lesson, keeping: present, context: context
            )
            if plan.isInserted {
                created.append(plan)
            } else {
                schedules.append(ScheduleSnapshot(plan))
            }
            plan.schedule(onDay: day)
        }
        guard !moved.isEmpty else { return nil }

        // Inserted plans need ids that outlive the save for Undo to find them.
        try? context.obtainPermanentIDs(for: created)
        let receipt = Receipt(
            movedStudentIDs: moved,
            createdPlanIDs: created.map(\.objectID),
            rosters: rosters,
            schedules: schedules,
            entries: entries
        )
        // Today shows `MoveError.saveFailed` in a toast, so the global alert stays quiet.
        guard saveCoordinator.save(
            context, reason: "Move absent children to tomorrow", alertOnFailure: false
        ) else {
            restore(receipt, in: context)
            throw MoveError.saveFailed
        }
        PresentationDetailUtilities.notifyInboxRefresh()
        return receipt
    }

    /// Takes a move back: the plans it made go, the children return to their
    /// lessons, and every schedule and year-plan entry is as it was.
    static func undo(
        _ receipt: Receipt,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws {
        restore(receipt, in: context)
        guard saveCoordinator.save(context, reason: "Undo moving absent children", alertOnFailure: false) else {
            throw MoveError.undoSaveFailed
        }
        PresentationDetailUtilities.notifyInboxRefresh()
    }

    // MARK: - Private

    private static func yearPlanEntries(
        lessonID: String,
        studentIDs: Set<UUID>,
        context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID IN %@", lessonID, studentIDs.map(\.uuidString)
        )
        return context.safeFetch(request)
    }

    /// Writes the receipt's "before" back, without saving.
    private static func restore(_ receipt: Receipt, in context: NSManagedObjectContext) {
        for id in receipt.createdPlanIDs {
            if let plan = try? context.existingObject(with: id), !plan.isDeleted {
                context.delete(plan)
            }
        }
        for roster in receipt.rosters {
            guard let assignment = object(roster.objectID, CDLessonAssignment.self, in: context) else { continue }
            assignment.studentIDs = roster.studentIDs
            assignment.modifiedAt = Date()
        }
        for snapshot in receipt.schedules {
            guard let assignment = object(snapshot.objectID, CDLessonAssignment.self, in: context) else { continue }
            assignment.stateRaw = snapshot.stateRaw
            assignment.scheduledFor = snapshot.scheduledFor
            assignment.scheduledForDay = snapshot.scheduledForDay
            assignment.modifiedAt = Date()
        }
        for snapshot in receipt.entries {
            guard let entry = object(snapshot.objectID, CDYearPlanEntry.self, in: context) else { continue }
            entry.statusRaw = snapshot.statusRaw
            entry.promotedAssignmentID = snapshot.promotedAssignmentID
        }
    }

    private static func object<T: NSManagedObject>(
        _ id: NSManagedObjectID, _ type: T.Type, in context: NSManagedObjectContext
    ) -> T? {
        guard let object = (try? context.existingObject(with: id)) as? T, !object.isDeleted else { return nil }
        return object
    }
}
