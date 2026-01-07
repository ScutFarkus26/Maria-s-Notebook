// StudentChecklistTabCoordinator.swift
// Coordinator for checklist tab actions extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentChecklistTabCoordinator {
    let vm: StudentDetailViewModel
    let checklistVM: StudentChecklistViewModel
    let modelContext: ModelContext
    let saveCoordinator: SaveCoordinator
    let selectedContract: Binding<WorkContract?>
    
    func handleTapScheduled(lesson: Lesson, row: StudentChecklistRowState?) {
        if let pid = row?.plannedItemID, 
           let sl = vm.studentLessons.first(where: { $0.id == pid }) {
            vm.selectedStudentLessonForDetail = sl
        } else {
            let draft = vm.createOrReuseNonGivenStudentLesson(for: lesson, modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Create or reuse non-given student lesson")
            vm.loadData(modelContext: modelContext)
            vm.selectedStudentLessonForDetail = draft
            checklistVM.recompute(for: vm.lessons, using: modelContext)
        }
    }
    
    func handleTapPresented(lesson: Lesson, row: StudentChecklistRowState?) {
        if let presID = row?.presentationLogID, 
           let sl = vm.studentLessons.first(where: { $0.id == presID }) {
            vm.selectedStudentLessonForDetail = sl
        } else {
            let sl = vm.logPresentation(for: lesson, modelContext: modelContext)
            _ = vm.ensureWork(for: lesson, presentationStudentLesson: sl, modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Log presentation and ensure work")
            vm.loadData(modelContext: modelContext)
        }
    }
    
    func handleTapActive(lesson: Lesson, row: StudentChecklistRowState?) {
        // Try to find WorkModel first
        if let workID = row?.contractID,
           let work = vm.fetchWork(by: workID, modelContext: modelContext) {
            // Use legacy adapter to find WorkContract if needed for UI compatibility
            if let legacyID = work.legacyContractID {
                // Try to find WorkContract directly (for legacy UI compatibility)
                let allContracts = (try? modelContext.fetch(FetchDescriptor<WorkContract>())) ?? []
                if let contract = allContracts.first(where: { $0.id == legacyID }) {
                    selectedContract.wrappedValue = contract
                }
            }
        } else if (row?.isPresented ?? false) {
            if let work = vm.ensureWork(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                _ = saveCoordinator.save(modelContext, reason: "Ensure work from checklist")
                // Try to find corresponding WorkContract for UI compatibility
                if let legacyID = work.legacyContractID {
                    let allContracts = (try? modelContext.fetch(FetchDescriptor<WorkContract>())) ?? []
                    if let contract = allContracts.first(where: { $0.id == legacyID }) {
                        selectedContract.wrappedValue = contract
                    }
                }
            }
        }
    }
    
    func handleTapComplete(lesson: Lesson, row: StudentChecklistRowState?) {
        if let workID = row?.contractID,
           let work = vm.fetchWork(by: workID, modelContext: modelContext),
           work.status != .complete {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
            _ = saveCoordinator.save(modelContext, reason: "Complete work from checklist")
            checklistVM.recompute(for: vm.lessons, using: modelContext)
        } else if (row?.isPresented ?? false) && row?.contractID == nil {
            if let work = vm.ensureWork(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                work.status = .complete
                work.completedAt = AppCalendar.startOfDay(Date())
                _ = saveCoordinator.save(modelContext, reason: "Create-and-complete work from checklist")
                checklistVM.recompute(for: vm.lessons, using: modelContext)
            }
        }
    }
}

