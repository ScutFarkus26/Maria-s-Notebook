// PresentationSessionCommit.swift
// What Done writes, in one save.
//
// Every write goes through the service the rest of the app uses for it:
// observations through PresentationOutcomePersistenceService, the per-child
// decisions through CaptureFollowUpPersistence (the command bar's and MCP
// record_presentation's path), the follow-up rows through
// PresentationFollowUpService, check-ins through WorkCheckInService, the
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
        /// The catalog, for the next lesson in the sequence.
        let lessons: [CDLesson]
    }

    struct Receipt: Equatable {
        var noteCount = 0
        var workCount = 0
        var checkInCount = 0
        var nextLessonPlanned = false
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
            context: context
        )
        receipt.noteCount = notes.count

        let entries = input.studentIDs.compactMap { id -> CaptureFollowUpPersistence.Entry? in
            guard let decision = input.decisions[id] else { return nil }
            let note = input.childNotes[id]?.trimmed() ?? ""
            // Keep watching only flags a note that exists; with none, the open
            // follow-up row is the reminder.
            let followUp: CaptureFollowUp = decision == .continueObserving && note.isEmpty ? .none : decision
            return CaptureFollowUpPersistence.Entry(
                studentID: id, observation: note, followUp: followUp, followUpDetail: ""
            )
        }
        receipt.workCount = try CaptureFollowUpPersistence.persist(
            entries,
            assignment: input.assignment,
            lesson: input.lesson,
            persistence: CapturePersistenceContext(
                lessonID: lessonID,
                lessonName: input.lesson.name,
                presentationID: presentationID,
                context: context
            )
        )

        updateFollowUpRows(input, presentationID: presentationID, context: context, now: now)
        receipt.checkInCount = try scheduleCheckIns(
            input, presentationID: presentationID, skipping: leftBehind, context: context
        )
        receipt.nextLessonPlanned = planNextLesson(input, context: context)
        return receipt
    }

    /// The guide's own follow-up, per child: work to check stays open with
    /// its date, a re-presentation or a next lesson closes it, and keep
    /// watching leaves it open.
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
            apply(
                decision,
                changed: input.decisions[studentID] != nil,
                to: row,
                reviewAt: input.checkIn.day,
                now: now
            )
        }
    }

    private static func apply(
        _ decision: CaptureFollowUp,
        changed: Bool,
        to row: CDLessonPresentation,
        reviewAt: Date?,
        now: Date
    ) {
        // An unchanged work-giving decision still takes a new check-in date.
        guard changed || (decision.createsWork && row.hasOpenFollowUp) else { return }
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

    /// Puts a check-in on the chosen day on each work-giving child's open work
    /// from this presentation, moving one already scheduled rather than adding
    /// a second.
    private static func scheduleCheckIns(
        _ input: Input,
        presentationID: UUID,
        skipping leftBehind: Set<NSManagedObjectID>,
        context: NSManagedObjectContext
    ) throws -> Int {
        guard let day = input.checkIn.day else { return 0 }
        let studentIDs = Set(input.studentIDs.filter { input.allDecisions[$0]?.createsWork == true }.map(\.uuidString))
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

    /// Children newly ready for the next lesson get it On Deck, as one plan,
    /// unless they are already on a plan for it.
    private static func planNextLesson(_ input: Input, context: NSManagedObjectContext) -> Bool {
        let ready = Set(input.decisions.filter { $0.value == .readyForNextLesson }.map(\.key))
        guard !ready.isEmpty,
              let next = PlanNextLessonService.findNextLesson(after: input.lesson, in: input.lessons),
              let nextID = next.id else { return false }

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", nextID.uuidString)
        let existing = context.safeFetch(request).filter { !$0.isPresented && !$0.isDeleted }
        let alreadyPlanned = Set(existing.flatMap(\.resolvedStudentIDs))
        let toPlan = ready.subtracting(alreadyPlanned)
        guard !toPlan.isEmpty else { return false }

        if case .success = PlanNextLessonService.planLesson(
            next,
            forStudents: toPlan,
            allStudents: [],
            allLessons: input.lessons,
            existingLessonAssignments: existing,
            context: context
        ) {
            return true
        }
        return false
    }
}
