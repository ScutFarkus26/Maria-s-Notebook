// TransitionPlannerViewModel.swift
// ViewModel for the Transition & Bridging Planner.

import CoreData
import SwiftUI

@Observable
@MainActor
final class TransitionPlannerViewModel {
    var plans: [CDTransitionPlan] = []
    var students: [CDStudent] = []
    var selectedStatusFilter: TransitionStatus?
    var showingNewPlanPicker = false

    var filteredPlans: [CDTransitionPlan] {
        guard let filter = selectedStatusFilter else { return plans }
        return plans.filter { $0.status == filter }
    }

    func loadData(context: NSManagedObjectContext) {
        let planRequest = CDFetchRequest(CDTransitionPlan.self)
        planRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransitionPlan.createdAt, ascending: false)]
        plans = context.safeFetch(planRequest)

        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.sortDescriptors = CDStudent.sortByName
        students = TestStudentsFilter.filterVisible(context.safeFetch(studentRequest).filter(\.isEnrolled))
    }

    func student(for plan: CDTransitionPlan) -> CDStudent? {
        guard let uuid = plan.studentUUID else { return nil }
        return students.first(where: { $0.id == uuid })
    }

    private func checklistItems(for plan: CDTransitionPlan) -> [CDTransitionChecklistItem] {
        (plan.checklistItems?.allObjects as? [CDTransitionChecklistItem]) ?? []
    }

    func readinessPercentage(for plan: CDTransitionPlan) -> Double {
        let items = checklistItems(for: plan)
        guard !items.isEmpty else { return 0 }
        let completed = items.filter(\.isCompleted).count
        return Double(completed) / Double(items.count)
    }

    func completedCount(for plan: CDTransitionPlan) -> Int {
        checklistItems(for: plan).filter(\.isCompleted).count
    }

    func totalCount(for plan: CDTransitionPlan) -> Int {
        checklistItems(for: plan).count
    }

    // MARK: - CRUD

    func createPlan(studentID: UUID, context: NSManagedObjectContext) {
        let plan = CDTransitionPlan(context: context)
        plan.id = UUID()
        plan.studentID = studentID.uuidString
        plan.fromLevelRaw = "Lower Elementary"
        plan.toLevelRaw = "Upper Elementary"
        plan.createdAt = Date()

        // Pre-populate checklist
        for (index, template) in TransitionChecklistTemplates.lowerToUpper.enumerated() {
            let item = CDTransitionChecklistItem(context: context)
            item.id = UUID()
            item.transitionPlanID = (plan.id ?? UUID()).uuidString
            item.title = template.title
            item.category = template.category
            item.sortOrder = Int64(index)
            item.transitionPlan = plan
        }

        context.safeSave()
        loadData(context: context)
    }

    func deletePlan(_ plan: CDTransitionPlan, context: NSManagedObjectContext) {
        context.delete(plan)
        context.safeSave()
        loadData(context: context)
    }

    func toggleChecklistItem(_ item: CDTransitionChecklistItem, context: NSManagedObjectContext) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        context.safeSave()
    }

    func updateStatus(_ plan: CDTransitionPlan, to status: TransitionStatus, context: NSManagedObjectContext) {
        plan.status = status
        plan.modifiedAt = Date()
        context.safeSave()
    }

    /// Students that don't already have a transition plan
    var availableStudents: [CDStudent] {
        let existingStudentIDs = Set(plans.compactMap(\.studentUUID))
        return students.filter { student in
            guard let id = student.id else { return false }
            return !existingStudentIDs.contains(id)
        }
    }
}
