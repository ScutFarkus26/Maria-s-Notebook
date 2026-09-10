//
//  YearPlanReleaseService.swift
//  Maria's Notebook
//
//  Giving a lesson today retires the plan to give it on Thursday.
//
//  Whether an intention has been answered is derived — see
//  `YearPlanSatisfaction`, which reads the presentation record rather than a
//  flag, so it needs no write and settles across devices on its own. But a
//  *plan on the calendar* is not derived. A child promoted into Thursday's
//  group who receives the lesson this morning with another group is still on
//  Thursday's roster, and nothing about her history takes her off it: the
//  guide would arrive on Thursday to a group that no longer needs her.
//
//  So this is the one write recording still makes to the planning side. It
//  runs inside `LifecycleService.recordPresentation` — the single path both the
//  in-app capture review and MCP's `record_presentation` take — so the two
//  cannot drift apart.
//
//  Scope is deliberately narrow. Only a child whose year-plan entry names the
//  other plan (`promotedAssignmentID`) is released from it: that pointer is
//  what says "this plan exists to answer that intention, and the intention is
//  answered now". A group the guide assembled by hand, with no year-plan entry
//  behind it, is her arrangement to change. Plans already given are history and
//  are never touched.
//

import CoreData
import Foundation
import OSLog

enum YearPlanReleaseService {
    private static let logger = Logger.app(category: "YearPlanRelease")

    /// What one call changed. Returned so callers can log something meaningful.
    struct Outcome: Equatable {
        /// Other plans a child came off that still have someone on them.
        var rostersTrimmed: Int = 0
        /// Other plans deleted because the last child came off them.
        var plansDiscarded: Int = 0

        var isEmpty: Bool { rostersTrimmed == 0 && plansDiscarded == 0 }
    }

    /// Takes the children on this presentation off any *other* pending plan for
    /// the same lesson that they were promoted into.
    ///
    /// Does not save — the recording flows own their own save. Idempotent: the
    /// second run finds nobody left to release.
    @discardableResult
    static func releaseRedundantPlans(
        after assignment: CDLessonAssignment,
        in context: NSManagedObjectContext,
        dryRun: Bool = false
    ) -> Outcome {
        guard !assignment.lessonID.isEmpty else { return Outcome() }
        let assignmentID = assignment.id?.uuidString

        // Group by plan first, so two girls released from the same Thursday
        // group are one decision about that group rather than two — which is
        // what makes "she was the last one on it" come out right.
        var releases: [String: Set<String>] = [:]
        for entry in promotedEntries(
            lessonID: assignment.lessonID, studentIDs: assignment.studentIDs, in: context
        ) {
            guard let otherID = entry.promotedAssignmentID, otherID != assignmentID else { continue }
            releases[otherID, default: []].insert(entry.studentID)
        }
        guard !releases.isEmpty else { return Outcome() }

        var outcome = Outcome()
        for (planID, studentIDs) in releases {
            let result = release(studentIDs, fromPlan: planID, in: context, dryRun: dryRun)
            outcome.rostersTrimmed += result.rostersTrimmed
            outcome.plansDiscarded += result.plansDiscarded
        }

        if !outcome.isEmpty && !dryRun {
            let lesson = assignment.lessonID
            logger.info(
                """
                Lesson \(lesson, privacy: .public) given: trimmed \
                \(outcome.rostersTrimmed, privacy: .public) redundant plan roster(s), discarded \
                \(outcome.plansDiscarded, privacy: .public)
                """
            )
        }
        return outcome
    }

    // MARK: - Lookup

    /// Entries for this lesson and these children that point at some plan.
    /// Not `fetchLimit = 1`: a store that has been through a duplicating
    /// migration can carry more than one entry for the same pair, and each may
    /// name a different plan.
    private static func promotedEntries(
        lessonID: String, studentIDs: [String], in context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        guard !studentIDs.isEmpty else { return [] }
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID IN %@ AND statusRaw == %@ AND promotedAssignmentID != nil",
            lessonID, studentIDs, YearPlanEntryStatus.promoted.rawValue
        )
        return context.safeFetch(request)
    }

    // MARK: - The Other Plan

    private static func release(
        _ studentIDs: Set<String>,
        fromPlan planID: String,
        in context: NSManagedObjectContext,
        dryRun: Bool
    ) -> Outcome {
        guard let uuid = UUID(uuidString: planID),
              let other = context.object(CDLessonAssignment.self, id: uuid),
              !other.isPresented
        else { return Outcome() }

        let remaining = other.studentIDs.filter { !studentIDs.contains($0) }
        guard remaining.count != other.studentIDs.count else { return Outcome() }

        guard remaining.isEmpty else {
            guard !dryRun else { return Outcome(rostersTrimmed: 1) }
            // The same pair of writes the detail view's Save and MCP's
            // update_presentation_roster make.
            other.studentIDs = remaining
            other.confirmedStudentIDs = other.confirmedStudentIDs.filter { remaining.contains($0) }
            other.modifiedAt = Date()
            return Outcome(rostersTrimmed: 1)
        }

        guard !dryRun else { return Outcome(plansDiscarded: 1) }
        // Every entry still pointing at this plan loses what it was pointing
        // at, so send it back to planned rather than leaving it promoted into
        // nothing — the repair `discard_presentation` makes. The ones this call
        // just answered read as given either way, from the record.
        for stranded in entriesPromoted(into: planID, in: context) {
            stranded.status = .planned
            stranded.promotedAssignmentID = nil
        }
        context.delete(other)
        return Outcome(plansDiscarded: 1)
    }

    /// Entries still promoted into a given plan.
    private static func entriesPromoted(
        into planID: String, in context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "promotedAssignmentID == %@", planID)
        return context.safeFetch(request).filter(\.isPromoted)
    }
}
