//
//  WorkDeletionService.swift
//  Maria's Notebook
//
//  Taking a child off a work item, and deleting work items, without leaving
//  the records around them disagreeing.
//
//  Two facts shape everything here. First, a child is "on" a work item through
//  either of two fields — `CDWorkModel.studentID` (the owner) or a
//  `CDWorkParticipantEntity` row — and the schema keeps neither in step with
//  the other. Second, several records key work by its id *string* with no
//  relationship: check-ins dropped from the week plan, completion records,
//  meeting reviews and scheduled meetings. `context.delete(work)` cascades
//  none of those, and a delete counted only through relationships under-reports
//  what it destroys.
//
//  Removing an owner is the case that bites. On a shared row the owner is the
//  child named in `studentID`; a literal "delete the row she owns" takes every
//  other child on that row with her. So removal of an owner is a
//  self-participant delete plus promotion of a remaining participant into
//  `studentID` — the rule `SessionWorkAssignmentService.removeSelection`
//  already follows for project work. Only when the row is one of several
//  linked copies is it truly hers alone, and only then is it deleted.
//
//  Nothing here saves on its own. Each operation runs inside a
//  `ContextMutationTransaction` and is rolled back if the caller's persist
//  step fails, so a failed save leaves no half-removed child behind.
//

import CoreData
import Foundation
import OSLog

/// What a work item costs to delete: the records that go with it and the
/// records left pointing at nothing.
struct WorkCascade: Equatable {
    var participants = 0
    /// Observations written against the work (`unifiedNotes` cascades).
    var observations = 0
    var completionRecords = 0
    /// Counted through the relationship and the `workID` string both.
    var checkIns = 0
    var steps = 0
    /// Left in place and reported: the meeting happened, and erasing what was
    /// reviewed would be a second falsification.
    var meetingReviews = 0
    /// Their `workID` is cleared; the meeting itself stands.
    var scheduledMeetings = 0

    static func + (lhs: WorkCascade, rhs: WorkCascade) -> WorkCascade {
        WorkCascade(
            participants: lhs.participants + rhs.participants,
            observations: lhs.observations + rhs.observations,
            completionRecords: lhs.completionRecords + rhs.completionRecords,
            checkIns: lhs.checkIns + rhs.checkIns,
            steps: lhs.steps + rhs.steps,
            meetingReviews: lhs.meetingReviews + rhs.meetingReviews,
            scheduledMeetings: lhs.scheduledMeetings + rhs.scheduledMeetings
        )
    }
}

/// Exactly what taking one child off one work item will change.
///
/// Built before anything is touched so the caller can show it, and applied
/// verbatim afterwards so what was shown is what happens.
struct WorkRemovalPlan {
    enum Action: Hashable {
        /// Her participant row on this row goes; nobody else is touched.
        case dropParticipant
        /// She owns this row and it is shared: her participant row goes and
        /// the named child becomes the owner.
        case promote(to: UUID)
        /// She owns this row and it is one of several linked copies, so it is
        /// hers alone: the row and everything cascading from it go.
        case deleteRow
        /// Offered project work may legitimately have no children; her
        /// participant row goes and the owner field is cleared.
        case clearOwner
    }

    struct Step {
        let work: CDWorkModel
        let action: Action
    }

    let studentID: UUID
    /// The group the anchor row belongs to, for reporting its shape.
    let group: WorkGroup
    /// One step per row in the group she is on, in group order.
    let steps: [Step]
    /// Her completion records on the rows above; deleted with her.
    let completionRecords: [CDWorkCompletionRecord]

    var works: [CDWorkModel] { steps.map(\.work) }
}

struct WorkDeletionService {
    private static let logger = Logger.work

    enum ServiceError: LocalizedError, Equatable {
        case studentNotOnWork
        /// Removing her would leave a row with no child on it. Deleting the
        /// row is a different decision, so this refuses rather than escalates.
        case wouldEmptyRow
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .studentNotOnWork:
                return "That child is not on this work."
            case .wouldEmptyRow:
                return "That child is the only one left on this work. Delete the work instead."
            case .saveFailed:
                return "The change could not be saved."
            }
        }
    }

    let context: NSManagedObjectContext

    // MARK: - Inspection

    /// Every check-in for a work item: those attached through the relationship
    /// and those that only carry the `workID` string. The week-plan drop path
    /// writes `workID` without setting `work`, so a relationship-only read
    /// misses them.
    static func checkIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        var candidates = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        if let workID = work.id?.uuidString {
            let request = CDFetchRequest(CDWorkCheckIn.self)
            request.predicate = NSPredicate(format: "workID == %@", workID)
            candidates.append(contentsOf: context.safeFetch(request))
        }
        var seen = Set<NSManagedObjectID>()
        return candidates.filter { seen.insert($0.objectID).inserted }
    }

    /// What deleting `work` destroys and what it leaves dangling.
    func cascade(for work: CDWorkModel) -> WorkCascade {
        var cascade = WorkCascade()
        cascade.participants = work.participants?.count ?? 0
        cascade.observations = ((work.unifiedNotes?.allObjects as? [CDNote]) ?? [])
            .filter { !$0.body.trimmed().isEmpty }.count
        cascade.checkIns = Self.checkIns(of: work, in: context).count
        cascade.steps = work.steps?.count ?? 0
        guard let workID = work.id?.uuidString else { return cascade }
        cascade.completionRecords = completionRecords(workID: workID).count
        cascade.meetingReviews = meetingReviews(workID: workID).count
        cascade.scheduledMeetings = scheduledMeetings(workID: workID).count
        return cascade
    }

    /// Resolves what removing `studentID` from the group containing `work`
    /// will change, touching nothing.
    func removalPlan(for studentID: UUID, from work: CDWorkModel) throws -> WorkRemovalPlan {
        let group = WorkGrouping.group(containing: work, in: context)
        let involved = group.members.filter { WorkGrouping.involves(studentID, in: $0) }
        guard !involved.isEmpty else { throw ServiceError.studentNotOnWork }

        let isLinkedCopies = group.members.count > 1
        var steps: [WorkRemovalPlan.Step] = []
        for member in involved {
            let action: WorkRemovalPlan.Action
            if WorkGrouping.owner(of: member) == studentID {
                if isLinkedCopies {
                    action = .deleteRow
                } else if let heir = Self.heir(after: studentID, on: member) {
                    action = .promote(to: heir)
                } else if member.sourceContextType == .projectSession {
                    action = .clearOwner
                } else {
                    throw ServiceError.wouldEmptyRow
                }
            } else {
                action = .dropParticipant
            }
            steps.append(.init(work: member, action: action))
        }

        let records = steps.compactMap { $0.work.id?.uuidString }
            .flatMap { completionRecords(workID: $0, studentID: studentID) }
        return WorkRemovalPlan(
            studentID: studentID, group: group, steps: steps, completionRecords: records
        )
    }

    /// The participant who takes over `studentID`'s row when she leaves it.
    ///
    /// `removeSelection` takes whichever participant the set yields first;
    /// this picks by id so the same row always promotes the same child and the
    /// plan a guide confirms is the plan that runs.
    static func heir(after studentID: UUID, on work: CDWorkModel) -> UUID? {
        WorkGrouping.studentIDs(of: work)
            .filter { $0 != studentID }
            .min { $0.uuidString < $1.uuidString }
    }

    // MARK: - Removal

    /// Takes `studentID` off every row of the group containing `work`,
    /// following the plan `removalPlan` reports.
    ///
    /// Writes no completion; touches no other child's `completedAt`. Her own
    /// completion records on the affected rows are deleted with her.
    @discardableResult
    func remove(
        studentID: UUID,
        from work: CDWorkModel,
        persist: (() -> Bool)? = nil
    ) throws -> WorkRemovalPlan {
        let plan = try removalPlan(for: studentID, from: work)
        try apply(plan, persist: persist)
        return plan
    }

    /// Applies a plan built earlier by `removalPlan`, so what the guide was
    /// shown is exactly what runs.
    func apply(_ plan: WorkRemovalPlan, persist: (() -> Bool)? = nil) throws {
        let transaction = ContextMutationTransaction(context: context)
        for step in plan.steps {
            switch step.action {
            case .dropParticipant:
                dropParticipantRows(for: plan.studentID, on: step.work)
            case .promote(let heir):
                dropParticipantRows(for: plan.studentID, on: step.work)
                step.work.studentID = heir.uuidString
            case .clearOwner:
                dropParticipantRows(for: plan.studentID, on: step.work)
                step.work.studentID = ""
            case .deleteRow:
                deleteRow(step.work, survivingSiblings: plan.group.members.filter { $0 !== step.work })
            }
        }
        for record in plan.completionRecords where !record.isDeleted {
            context.delete(record)
        }

        let didSave = persist?() ?? context.safeSave()
        guard didSave else {
            transaction.rollback()
            throw ServiceError.saveFailed
        }
        transaction.commit()
        Self.logger.info("Removed a child from \(plan.steps.count) work row(s)")
    }

    /// Takes `studentID` off every row in `works` that names her, for callers
    /// that batch many changes into one save of their own. A row she is the
    /// last child on is deleted, since leaving her on it is the one outcome
    /// the caller has ruled out. Never saves.
    static func removeWithoutSaving(
        studentID: UUID, from works: [CDWorkModel], in context: NSManagedObjectContext
    ) {
        let service = WorkDeletionService(context: context)
        var handled = Set<NSManagedObjectID>()
        for work in works where !handled.contains(work.objectID) && !work.isDeleted {
            guard WorkGrouping.involves(studentID, in: work) else { continue }
            do {
                let plan = try service.removalPlan(for: studentID, from: work)
                for touched in plan.works { handled.insert(touched.objectID) }
                try service.apply(plan) { true }
            } catch ServiceError.wouldEmptyRow {
                handled.insert(work.objectID)
                try? service.delete([work]) { true }
            } catch {
                logger.error("Could not remove a child from work: \(error)")
            }
        }
    }

    // MARK: - Deletion

    /// Deletes `works` together with the records that only exist for them,
    /// and strips the deleted owners from the linked copies that survive —
    /// the residue `context.delete(work)` on its own leaves behind, which
    /// reads afterwards as a passenger nobody put there.
    @discardableResult
    func delete(_ works: [CDWorkModel], persist: (() -> Bool)? = nil) throws -> WorkCascade {
        let total = works.reduce(WorkCascade()) { $0 + cascade(for: $1) }
        let transaction = ContextMutationTransaction(context: context)
        for work in works where !work.isDeleted {
            let siblings = WorkGrouping.group(containing: work, in: context).siblings
                .filter { sibling in !works.contains { $0 === sibling } }
            deleteRow(work, survivingSiblings: siblings)
        }

        let didSave = persist?() ?? context.safeSave()
        guard didSave else {
            transaction.rollback()
            throw ServiceError.saveFailed
        }
        transaction.commit()
        return total
    }

    // MARK: - Private

    private func deleteRow(_ work: CDWorkModel, survivingSiblings: [CDWorkModel]) {
        if let owner = WorkGrouping.owner(of: work) {
            for sibling in survivingSiblings {
                dropParticipantRows(for: owner, on: sibling)
            }
        }
        if let workID = work.id?.uuidString {
            for record in completionRecords(workID: workID) {
                context.delete(record)
            }
            for checkIn in Self.checkIns(of: work, in: context) {
                context.delete(checkIn)
            }
            for meeting in scheduledMeetings(workID: workID) {
                meeting.workID = nil
            }
        }
        context.delete(work)
    }

    private func dropParticipantRows(for studentID: UUID, on work: CDWorkModel) {
        let idString = studentID.uuidString
        let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        for participant in participants where participant.studentID == idString {
            context.delete(participant)
        }
    }

    private func completionRecords(workID: String, studentID: UUID? = nil) -> [CDWorkCompletionRecord] {
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        if let studentID {
            request.predicate = NSPredicate(
                format: "workID == %@ AND studentID == %@", workID, studentID.uuidString
            )
        } else {
            request.predicate = NSPredicate(format: "workID == %@", workID)
        }
        return context.safeFetch(request)
    }

    private func meetingReviews(workID: String) -> [CDMeetingWorkReview] {
        let request = CDFetchRequest(CDMeetingWorkReview.self)
        request.predicate = NSPredicate(format: "workID == %@", workID)
        return context.safeFetch(request)
    }

    private func scheduledMeetings(workID: String) -> [CDScheduledMeeting] {
        let request = CDFetchRequest(CDScheduledMeeting.self)
        request.predicate = NSPredicate(format: "workID == %@", workID)
        return context.safeFetch(request)
    }
}
