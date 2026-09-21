//
//  PresentationWorkRetraction.swift
//  Cosmic Daybook
//
//  The work a presentation already generated for a child who is being taken
//  off it.
//
//  `PresentationFollowUpWorkService` creates work from the presentation's
//  participant list. Editing that list afterwards changes the presentation
//  and nothing downstream, so the work rows go on naming a child the
//  presentation no longer does. Rather than leave the two records
//  disagreeing, removal from a presentation names the affected work rows and
//  offers to take her off them through `WorkDeletionService` — which knows
//  the difference between a row she owns and one she is only a passenger on.
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
                guard let plan = try? service.removalPlan(for: studentID, from: row) else {
                    // She is the last child on the row: taking her off would
                    // empty it. Left for the guide to delete deliberately.
                    continue
                }
                for touched in plan.works { covered.insert(touched.objectID) }
                plans.append(plan)
            }
            covered.removeAll()
        }
        return plans
    }

    /// Applies plans built by `plans(forRemoving:from:in:)`. Does not save;
    /// the caller's save decides whether any of it lands.
    static func apply(_ plans: [WorkRemovalPlan], in context: NSManagedObjectContext) throws {
        let service = WorkDeletionService(context: context)
        for plan in plans {
            try service.apply(plan) { true }
        }
    }

    /// One line per row, for the confirmation: who, which row, what happens.
    static func describe(_ plans: [WorkRemovalPlan], in context: NSManagedObjectContext) -> [String] {
        let students = StudentRepository(context: context)
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
                case .deleteRow:
                    return "\(name)’s own copy of “\(title)” is deleted"
                }
            }
        }
    }
}
