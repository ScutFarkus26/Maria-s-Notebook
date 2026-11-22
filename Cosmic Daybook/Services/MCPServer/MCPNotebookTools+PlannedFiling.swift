//
//  MCPNotebookTools+PlannedFiling.swift
//  Cosmic Daybook
//
//  `record_presentation`'s `planned_presentation_id`, and when the practice it
//  files comes back (plan "Cut unused features and close the lesson loop",
//  2026-11-21).
//
//  A planned lesson given to a slightly different group used to leave the
//  plan behind: `PresentationRecorder.resolvePlan` only takes a plan holding
//  every child named. Naming the plan closes it: the record takes the plan
//  over and adds any child who wasn't on it, and a child on it who wasn't
//  there stays planned on it, on its day (the split the in-app resolution
//  already makes, `PresentationSplitService.splitReadyStudents`). A child
//  added this way passes the regive guard as one named on a new record
//  does; the children already on the plan passed it when it was made.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Reading the argument

    /// The plan `planned_presentation_id` names, refusing one that isn't a
    /// waiting plan.
    static func plannedPresentation(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> CDLessonAssignment? {
        guard let reference = nonEmpty(arguments["planned_presentation_id"]?.stringValue) else { return nil }
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("planned_presentation_id must be a presentation id, got \"\(reference)\".")
        }
        guard let plan = PresentationRepository(context: modelContext).fetchLessonAssignment(id: id),
              !plan.isDeleted else {
            throw MCPToolError("No planned presentation with id \(reference) was found.")
        }
        guard !plan.isGiven else {
            throw MCPToolError(
                "That plan has already been recorded as given. To change what was filed, call "
                    + "record_presentation again without planned_presentation_id (the same lesson, "
                    + "children and day update it)."
            )
        }
        return plan
    }

    /// The filing's lesson: the one named, which must be the plan's when both
    /// are given, or the plan's own.
    static func filingLesson(
        _ arguments: [String: JSONValue],
        plan: CDLessonAssignment?,
        lessons: LessonReferences,
        in modelContext: NSManagedObjectContext
    ) throws -> CDLesson {
        let named = try nonEmpty(arguments["lesson"]?.stringValue).map { try lessons.resolve($0) }
        guard let plan else {
            guard let named else { return try lessons.resolve(requireString(arguments, "lesson")) }
            return named
        }
        let planned = plan.lesson ?? UUID(uuidString: plan.lessonID).flatMap {
            modelContext.object(CDLesson.self, id: $0)
        }
        guard let planned else {
            throw MCPToolError("That plan's lesson is no longer in the library, so it can't be recorded.")
        }
        if let named, named.id != planned.id {
            throw MCPToolError(
                "That plan is for \(planned.name), not \(named.name). Pass the plan for the lesson given, "
                    + "or leave planned_presentation_id out."
            )
        }
        return planned
    }

    /// One plan completed twice in one call would be split against itself.
    static func refuseSharedPlans(_ filings: [PresentationFiling]) throws {
        var seen = Set<NSManagedObjectID>()
        for plan in filings.compactMap(\.plan) where !seen.insert(plan.objectID).inserted {
            let name = plan.lesson?.name ?? "a lesson"
            throw MCPToolError(
                "Two presentations in this call name the same plan (\(name)). Name each plan once; "
                    + "nothing was recorded."
            )
        }
    }

    // MARK: - Taking the plan over

    /// The record a filing that names its plan lands on, or nil when nobody
    /// on the plan was there (it then resolves as any filing does, and the
    /// plan stays).
    static func takeOverPlan(
        _ filing: PresentationFiling, index: PresentationRecordIndex, in modelContext: NSManagedObjectContext
    ) -> ResolvedFiling? {
        guard let plan = filing.plan else { return nil }
        let onPlan = Set(plan.resolvedStudentIDs)
        let present = filing.studentIDs.filter(onPlan.contains)
        guard !present.isEmpty else { return nil }

        let assignment: CDLessonAssignment
        if Set(present) == onPlan {
            assignment = plan
        } else if let split = PresentationSplitService.splitReadyStudents(
            from: plan, readyStudentIDs: present, asDraft: true, context: modelContext
        ) {
            assignment = split
        } else {
            return nil
        }

        // Children named who weren't on the plan join it, through the guard.
        let joining = filing.students.filter { $0.id.map { !onPlan.contains($0) } ?? false }
        let conflicts = joining.isEmpty ? [] : repeatConflicts(
            lessonID: filing.lessonID.uuidString, students: joining, before: filing.presentedAt, index: index
        )
        if !joining.isEmpty {
            writeRoster(
                assignment.studentIDs + joining.compactMap { $0.id?.uuidString },
                to: assignment, in: modelContext
            )
        }
        return ResolvedFiling(filing: filing, assignment: assignment, origin: .plannedLesson, conflicts: conflicts)
    }

    // MARK: - Practice coming back

    /// The guide's decisions, with each work-giving child's check-in on the
    /// day `PracticeCheckInTiming` gives her. Returns how many work items
    /// were made.
    static func persistOutcomes(
        _ filing: PresentationFiling,
        assignment: CDLessonAssignment,
        presentationID: UUID,
        sequences: WorkToShowFirst.Sequences,
        in modelContext: NSManagedObjectContext
    ) throws -> Int {
        let working = Set(filing.outcomes.filter { $0.followUp.createsWork }.map(\.studentID))
        let days = working.isEmpty ? [:] : PracticeCheckInTiming.checkInDays(
            lessonID: filing.lessonID.uuidString, givenOn: filing.presentedAt, studentIDs: working,
            sequences: sequences, in: modelContext
        )
        let persistence = CapturePersistenceContext(
            lessonID: filing.lessonID,
            lessonName: filing.lesson.name,
            presentationID: presentationID,
            context: modelContext
        )
        var workCount = 0
        // One pass per check-in day: each child's follow-up row carries hers.
        for (day, entries) in Dictionary(grouping: filing.outcomes, by: { days[$0.studentID] }) {
            workCount += try CaptureFollowUpPersistence.persist(
                entries, assignment: assignment, lesson: filing.lesson, persistence: persistence, reviewAt: day
            )
        }
        PracticeCheckInTiming.scheduleCheckIns(forWorkFrom: presentationID, on: days, in: modelContext)
        return workCount
    }
}
