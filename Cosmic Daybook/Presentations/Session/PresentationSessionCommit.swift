// PresentationSessionCommit.swift
// What Done writes, in one save.
//
// Every write goes through the service the rest of the app uses for it:
// observations through PresentationOutcomePersistenceService, the per-child
// decisions and their follow-up rows through CaptureFollowUpPersistence (the
// command bar's and MCP record_presentation's path), check-ins through WorkCheckInService, the
// next lesson through PlanNextLessonService, and untouched work a changed
// decision leaves behind through WorkDeletionService. All of it lands or none
// of it does.

import CoreData
import Foundation

enum PresentationSessionCommit {
    struct Input {
        let assignment: CDLessonAssignment
        let lesson: CDLesson
        /// The children the presentation was recorded for.
        let studentIDs: [UUID]
        let groupNote: String
        let childNotes: [UUID: String]
        /// Only the children whose decision changes.
        let decisions: [UUID: CaptureFollowUp]
        /// Every child's decision, for the check-in date on work-giving ones.
        let allDecisions: [UUID: CaptureFollowUp]
        let checkIn: PresentationCheckIn
        /// Each work-giving child's own check-in day, from practice timing,
        /// when the guide didn't pick one; `checkIn` is the day for anyone
        /// not in it.
        var timedCheckIns: [UUID: Date] = [:]
        /// Whether the check-in day moved on the sheet (picked, or changed
        /// from the one on the record). When it didn't, a child whose
        /// decision is unchanged keeps her follow-up row's day and her
        /// check-in as they are, so reopening How It Went to add a note moves
        /// nobody's day (Phase 7 review of "Tide list clean-up 2026-11").
        var checkInMoved = true
        /// The catalog, for the next lesson in the sequence.
        let lessons: [CDLesson]
        /// The new follow-up work's title; blank gives "Follow up: <lesson>".
        var followUpDetail = ""
        /// Children newly ready for the next lesson alongside their practice
        /// or follow-up work.
        var alsoReady: Set<UUID> = []
        /// Children confirmed ready on the record whom the guide no longer marks ready.
        var noLongerReady: Set<UUID> = []
        /// Where the next lesson goes for the newly ready children. Nil leaves
        /// it to the year plan: its day if it has one, otherwise the Inbox.
        var nextLessonPlace: PresentationNextLessonPlace?

        /// The day `studentID`'s work comes back: her timed day, else the sheet's.
        func checkInDay(for studentID: UUID) -> Date? {
            timedCheckIns[studentID].map(AppCalendar.startOfDay) ?? checkIn.day
        }
    }

    struct Receipt: Equatable {
        var noteCount = 0
        var workCount = 0
        var checkInCount = 0
        var nextLessonPlanned = false
        /// The moment the new plan for the next lesson was put on; nil when it
        /// went to the Inbox or no plan was made.
        var nextLessonScheduledFor: Date?
        /// Work this commit created, for an Undo that has to take it away.
        var createdWorkIDs: [NSManagedObjectID] = []
    }

    enum CommitError: LocalizedError {
        case missingIdentity
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .missingIdentity:
                return "This presentation hasn't finished saving yet. Close it, open it again, and try once more."
            case .saveFailed:
                return "Couldn't save how the presentation went. Your notes are still here. Try again."
            }
        }
    }

    @discardableResult
    static func apply(
        _ input: Input,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        now: Date = Date()
    ) throws -> Receipt {
        guard let presentationID = input.assignment.id, let lessonID = input.lesson.id else {
            throw CommitError.missingIdentity
        }
        let transaction = ContextMutationTransaction(context: context)
        do {
            // Read before anything is written: the decisions' new work isn't
            // there yet, and the old work's check-ins haven't been moved.
            let leftBehind = untouchedWork(
                leftBehindBy: input.decisions, presentationID: presentationID, context: context
            )
            var receipt = try write(
                input, presentationID: presentationID, lessonID: lessonID,
                leftBehind: Set(leftBehind.map(\.objectID)), context: context, now: now
            )
            context.processPendingChanges()
            let createdWorks = context.insertedObjects
                .compactMap { $0 as? CDWorkModel }
                .filter { $0.presentationID == presentationID.uuidString }
            guard try save(retiring: leftBehind, context: context, saveCoordinator: saveCoordinator) else {
                throw CommitError.saveFailed
            }
            transaction.commit()
            // Read after the save: inserted objects carry temporary ids until then.
            receipt.createdWorkIDs = createdWorks.map(\.objectID)
            return receipt
        } catch {
            transaction.rollback()
            throw error
        }
    }

    /// The one save, with the left-behind work deleted inside it so a failed
    /// save puts that back as well.
    private static func save(
        retiring works: [CDWorkModel],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> Bool {
        // The caller shows `CommitError.saveFailed`, so the global alert stays quiet.
        let save = {
            saveCoordinator.save(context, reason: "Saving how the presentation went", alertOnFailure: false)
        }
        guard !works.isEmpty else { return save() }
        do {
            try WorkDeletionService(context: context).delete(works, persist: save)
            return true
        } catch WorkDeletionService.ServiceError.saveFailed {
            return false
        }
    }

    // MARK: - The writes

    // swiftlint:disable:next function_parameter_count
    private static func write(
        _ input: Input,
        presentationID: UUID,
        lessonID: UUID,
        leftBehind: Set<NSManagedObjectID>,
        context: NSManagedObjectContext,
        now: Date
    ) throws -> Receipt {
        var receipt = Receipt()

        let notes = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: input.groupNote,
            studentObservations: input.childNotes,
            studentIDs: input.studentIDs,
            presentationID: presentationID,
            // Dated the day it was given, not the day the notes were written (R10).
            observedOn: input.assignment.presentedAt,
            context: context
        )
        receipt.noteCount = notes.count

        // The changed decisions, and their follow-up rows, the one way Claude
        // and the command bar write them too (R6). Keep watching flags only a
        // note that exists; with none, the open follow-up row is the reminder.
        let entries = input.studentIDs.compactMap { id -> CaptureFollowUpPersistence.Entry? in
            guard let decision = input.decisions[id] else { return nil }
            return CaptureFollowUpPersistence.Entry(
                studentID: id, observation: input.childNotes[id]?.trimmed() ?? "", followUp: decision,
                followUpDetail: decision == .followUpWork ? input.followUpDetail : ""
            )
        }
        let persistence = CapturePersistenceContext(
            lessonID: lessonID,
            lessonName: input.lesson.name,
            presentationID: presentationID,
            context: context
        )
        // One pass per check-in day: each child's follow-up row carries hers.
        for (day, dayEntries) in Dictionary(grouping: entries, by: { input.checkInDay(for: $0.studentID) }) {
            receipt.workCount += try CaptureFollowUpPersistence.persist(
                dayEntries,
                assignment: input.assignment,
                lesson: input.lesson,
                persistence: persistence,
                reviewAt: day,
                now: now
            )
        }

        // Ready alongside work: confirmed as Ready for next confirms her; her
        // row stays open for the work.
        for id in input.studentIDs where input.alsoReady.contains(id) {
            input.assignment.confirmStudent(id)
        }
        for id in input.studentIDs where input.noLongerReady.contains(id) {
            input.assignment.unconfirmStudent(id)
        }

        updateFollowUpRows(input, presentationID: presentationID, context: context, now: now)
        receipt.checkInCount = try scheduleCheckIns(
            input, presentationID: presentationID, skipping: leftBehind, context: context
        )
        let nextPlan = planNextLesson(input, context: context)
        receipt.nextLessonPlanned = nextPlan != nil
        receipt.nextLessonScheduledFor = nextPlan?.scheduledFor
        return receipt
    }

    /// What `CaptureFollowUpPersistence` leaves to the sheet: an unchanged
    /// work-giving decision still takes the new check-in date, and a changed
    /// "no decision" goes back to watching, as the sheet has always read it
    /// (Claude's and the command bar's "none" leave the row alone).
    private static func updateFollowUpRows(
        _ input: Input,
        presentationID: UUID,
        context: NSManagedObjectContext,
        now: Date
    ) {
        let rows = PresentationFollowUpService.rows(for: presentationID, in: context)
        for row in rows {
            guard let studentID = UUID(uuidString: row.studentID),
                  let decision = input.allDecisions[studentID] else { continue }
            let changed = input.decisions[studentID] != nil
            let redate = !changed && decision.createsWork && row.hasOpenFollowUp && input.checkInMoved
            guard redate || (changed && decision == .none) else { continue }
            CaptureFollowUpPersistence.writeFollowUpRow(
                decision, to: row, reviewAt: input.checkInDay(for: studentID), now: now
            )
        }
    }

    /// Puts a check-in on each work-giving child's day (`Input.checkInDay`)
    /// on her open work from this presentation, moving one already scheduled
    /// rather than adding a second.
    private static func scheduleCheckIns(
        _ input: Input,
        presentationID: UUID,
        skipping leftBehind: Set<NSManagedObjectID>,
        context: NSManagedObjectContext
    ) throws -> Int {
        let studentIDs = Set(input.studentIDs.filter { id in
            input.allDecisions[id]?.createsWork == true && (input.checkInMoved || input.decisions[id] != nil)
        }.map(\.uuidString))
        guard !studentIDs.isEmpty else { return 0 }

        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        let works = context.safeFetch(request).filter {
            studentIDs.contains($0.studentID) && $0.status.isOpen && !$0.isDeleted
                && !leftBehind.contains($0.objectID)
        }
        let service = WorkCheckInService(context: context)
        var count = 0
        for work in works {
            guard let studentID = UUID(uuidString: work.studentID),
                  let day = input.checkInDay(for: studentID) else { continue }
            let scheduled = WorkDeletionService.checkIns(of: work, in: context)
                .filter { $0.status == .scheduled && !$0.isDeleted }
            if scheduled.contains(where: { AppCalendar.shared.isDate($0.date ?? .distantPast, inSameDayAs: day) }) {
                continue
            }
            if let existing = scheduled.first {
                try service.reschedule(existing, to: day)
            } else {
                try service.createCheckIn(for: work, date: day, purpose: "Review \(work.title)")
            }
            count += 1
        }
        return count
    }

    /// Children newly ready for the next lesson, on its own or alongside work,
    /// get it as one plan, unless they are already on a plan for it. The plan
    /// goes where the guide chose on the sheet: the Inbox, or a day with or
    /// without a start time. With no choice the year plan decides, as it
    /// always has: its day if it has one, otherwise the Inbox.
    private static func planNextLesson(_ input: Input, context: NSManagedObjectContext) -> CDLessonAssignment? {
        let ready = Set(input.decisions.filter { $0.value == .readyForNextLesson }.map(\.key))
            .union(input.alsoReady)
        guard !ready.isEmpty,
              let next = PlanNextLessonService.findNextLesson(after: input.lesson, in: input.lessons),
              let nextID = next.id else { return nil }

        let existing = PresentationNextLessonContext.unpresentedPlans(for: nextID, in: context)
        let alreadyPlanned = Set(existing.flatMap(\.resolvedStudentIDs))
        let toPlan = ready.subtracting(alreadyPlanned)
        guard !toPlan.isEmpty else { return nil }

        guard case .success(let plan) = PlanNextLessonService.planLesson(
            next,
            forStudents: toPlan,
            allStudents: [],
            allLessons: input.lessons,
            existingLessonAssignments: existing,
            context: context,
            autoPromoteFromYearPlan: input.nextLessonPlace == nil
        ) else { return nil }

        // A day the guide chose: the plan goes on it, and each child's
        // year-plan entry for the lesson follows it there. Nothing is laid on
        // the lessons after. The Inbox leaves the entries Planned where they are.
        if let moment = input.nextLessonPlace?.scheduledMoment() {
            plan.schedule(for: moment)
            YearPlanPromotionService.promoteMatchingEntries(into: plan, scheduledFor: moment, context: context)
            PracticeCheckInTiming.followPlannedLessons([plan], in: context)
        }
        return plan
    }
}

private extension CDLessonAssignment {
    /// Takes back a child's confirmation as ready for the next lesson.
    func unconfirmStudent(_ studentID: UUID) {
        let ids = confirmedStudentIDs
        guard ids.contains(studentID.uuidString) else { return }
        confirmedStudentIDs = ids.filter { $0 != studentID.uuidString }
        modifiedAt = Date()
    }
}
