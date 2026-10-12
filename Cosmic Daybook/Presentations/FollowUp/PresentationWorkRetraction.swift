//
//  PresentationWorkRetraction.swift
//  Cosmic Daybook
//
//  The work a presentation already generated for a child who is being taken
//  off it.
//
//  The presentation sheet's Done (`PresentationSessionCommit`) creates work
//  from the presentation's participant list. Editing that list afterwards changes the presentation
//  and nothing downstream, so the work rows go on naming a child the
//  presentation no longer does. Rather than leave the two records
//  disagreeing, removal from a presentation names the affected work rows and
//  offers to take her off them through `WorkDeletionService` — which knows
//  the difference between a row she owns and one she is only a passenger on.
//  Her own single-child row, the shape How It Went makes, is offered for
//  deletion: taking her off it would leave it naming nobody (bug hunt
//  2026-10-12 #47).
//

import CoreData
import Foundation

enum PresentationWorkRetraction {

    /// Every work row generated from `assignment`: linked by `presentationID`
    /// (the resolved assignment id `WorkRepository.createWork` writes) or by
    /// the follow-up service's source-context fields.
    static func generatedWork(
        for assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        guard let id = assignment.id?.uuidString else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ OR (sourceContextTypeRaw == %@ AND sourceContextID == %@)",
            id, WorkSourceContextType.presentation.rawValue, id
        )
        return context.safeFetch(request).uniqueByID
    }

    /// What taking `studentIDs` off `assignment` would change in its work:
    /// one plan per child per group of rows she is on. Touches nothing.
    static func plans(
        forRemoving studentIDs: Set<UUID>,
        from assignment: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) -> [WorkRemovalPlan] {
        let work = generatedWork(for: assignment, in: context)
        guard !work.isEmpty else { return [] }
        let service = WorkDeletionService(context: context)
        var plans: [WorkRemovalPlan] = []
        var covered = Set<NSManagedObjectID>()

        for studentID in studentIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            for row in work where WorkGrouping.involves(studentID, in: row) {
                guard !covered.contains(row.objectID) else { continue }
                let plan: WorkRemovalPlan
                do {
                    plan = try service.removalPlan(for: studentID, from: row)
                } catch WorkDeletionService.ServiceError.wouldEmptyRow {
                    // Her own row, with nobody else on it: the work this
                    // presentation gave her alone. Offered for deletion; the
                    // alert says so, and Keep the Work leaves it.
                    plan = ownRowDeletion(for: studentID, row: row, in: context)
                } catch {
                    continue
                }
                for touched in plan.works { covered.insert(touched.objectID) }
                plans.append(plan)
            }
            covered.removeAll()
        }
        return plans
    }

    /// Deleting `row`, which only `studentID` is on, applied by
    /// `WorkDeletionService.apply` like any other plan: the row goes with its
    /// check-ins and completion records.
    private static func ownRowDeletion(
        for studentID: UUID, row: CDWorkModel, in context: NSManagedObjectContext
    ) -> WorkRemovalPlan {
        WorkRemovalPlan(
            studentID: studentID,
            group: WorkGrouping.group(containing: row, in: context),
            steps: [.init(work: row, action: .deleteRow)],
            completionRecords: []
        )
    }

    /// Applies plans built by `plans(forRemoving:from:in:)`. Does not save,
    /// and takes no transaction of its own: the caller holds one around this
    /// and its save, so a failed save takes the retraction back with the rest
    /// (`PresentationDetailViewModel.save`).
    static func apply(_ plans: [WorkRemovalPlan], in context: NSManagedObjectContext) throws {
        let service = WorkDeletionService(context: context)
        for plan in plans {
            service.applyWithoutSaving(plan)
        }
    }

    /// One line per row, for the confirmation: who, which row, what happens.
    /// A row that is deleted says what goes with it, as the work grid's
    /// delete does: its notes and check-ins (bug hunt 2026-10-12 #47).
    static func describe(_ plans: [WorkRemovalPlan], in context: NSManagedObjectContext) -> [String] {
        let students = StudentRepository(context: context)
        let service = WorkDeletionService(context: context)
        return plans.flatMap { plan -> [String] in
            let name = students.fetchStudent(id: plan.studentID)
                .map { $0.shortName } ?? "This child"
            return plan.steps.map { step in
                let title = step.work.title.trimmed().isEmpty ? "Untitled work" : step.work.title
                switch step.action {
                case .dropParticipant:
                    return "\(name) comes off “\(title)”"
                case .promote(let heir):
                    let heirName = students.fetchStudent(id: heir)
                        .map { $0.shortName } ?? "another child"
                    return "\(name) comes off “\(title)”; \(heirName) becomes its owner"
                case .clearOwner:
                    return "\(name) comes off “\(title)”, which stays open and unclaimed"
                case .deleteRow where plan.group.members.count > 1:
                    return "\(name)’s own copy of “\(title)” is deleted"
                        + goingWith(service.cascade(for: step.work))
                case .deleteRow:
                    return "\(name)’s “\(title)” is deleted" + goingWith(service.cascade(for: step.work))
                }
            }
        }
    }

    /// ", with its 2 notes and 3 check-ins", or nothing when only the row goes.
    private static func goingWith(_ cascade: WorkCascade) -> String {
        var parts: [String] = []
        if cascade.observations > 0 {
            parts.append("\(cascade.observations) " + (cascade.observations == 1 ? "note" : "notes"))
        }
        if cascade.checkIns > 0 {
            parts.append("\(cascade.checkIns) " + (cascade.checkIns == 1 ? "check-in" : "check-ins"))
        }
        return parts.isEmpty ? "" : ", with its " + parts.joined(separator: " and ")
    }
}
