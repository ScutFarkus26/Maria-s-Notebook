// TransitionPlannerViewModel.swift
// ViewModel for the Transition & Bridging Planner.

import SwiftData
import SwiftUI

@Observable
@MainActor
final class TransitionPlannerViewModel {
    var plans: [TransitionPlan] = []
    var students: [Student] = []
    var selectedStatusFilter: TransitionStatus?
    var showingNewPlanPicker = false

    var filteredPlans: [TransitionPlan] {
        guard let filter = selectedStatusFilter else { return plans }
        return plans.filter { $0.status == filter }
    }

    func loadData(context: ModelContext) {
        let planDescriptor = FetchDescriptor<TransitionPlan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        plans = context.safeFetch(planDescriptor)

        let studentDescriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor).filter(\.isEnrolled))
    }

    func student(for plan: TransitionPlan) -> Student? {
        guard let uuid = plan.studentUUID else { return nil }
        return students.first(where: { $0.id == uuid })
    }

    func readinessPercentage(for plan: TransitionPlan) -> Double {
        let items = plan.checklistItems ?? []
        guard !items.isEmpty else { return 0 }
        let completed = items.filter(\.isCompleted).count
        return Double(completed) / Double(items.count)
    }

    func completedCount(for plan: TransitionPlan) -> Int {
        (plan.checklistItems ?? []).filter(\.isCompleted).count
    }

    func totalCount(for plan: TransitionPlan) -> Int {
        (plan.checklistItems ?? []).count
    }

    // MARK: - CRUD

    func createPlan(studentID: UUID, context: ModelContext) {
        let plan = TransitionPlan(
            studentID: studentID.uuidString,
            fromLevelRaw: "Lower Elementary",
            toLevelRaw: "Upper Elementary"
        )
        context.insert(plan)

        // Pre-populate checklist
        for (index, template) in TransitionChecklistTemplates.lowerToUpper.enumerated() {
            let item = TransitionChecklistItem(
                transitionPlanID: plan.id.uuidString,
                title: template.title,
                category: template.category,
                sortOrder: index
            )
            item.transitionPlan = plan
            context.insert(item)
        }

        context.safeSave()
        loadData(context: context)
    }

    func deletePlan(_ plan: TransitionPlan, context: ModelContext) {
        context.delete(plan)
        context.safeSave()
        loadData(context: context)
    }

    func toggleChecklistItem(_ item: TransitionChecklistItem, context: ModelContext) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        context.safeSave()
    }

    func updateStatus(_ plan: TransitionPlan, to status: TransitionStatus, context: ModelContext) {
        plan.status = status
        plan.modifiedAt = Date()
        context.safeSave()
    }

    /// Students that don't already have a transition plan
    var availableStudents: [Student] {
        let existingStudentIDs = Set(plans.compactMap(\.studentUUID))
        return students.filter { !existingStudentIDs.contains($0.id) }
    }
}
