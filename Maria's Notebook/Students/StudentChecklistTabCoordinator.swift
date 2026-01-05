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
            _ = vm.ensureContract(for: lesson, presentationStudentLesson: sl, modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Log presentation and ensure contract")
            vm.loadData(modelContext: modelContext)
        }
    }
    
    func handleTapActive(lesson: Lesson, row: StudentChecklistRowState?) {
        if let cid = row?.contractID, 
           let c = vm.fetchContract(by: cid, modelContext: modelContext) {
            selectedContract.wrappedValue = c
        } else if (row?.isPresented ?? false) {
            if let c = vm.ensureContract(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                _ = saveCoordinator.save(modelContext, reason: "Ensure contract from checklist")
                selectedContract.wrappedValue = c
            }
        }
    }
    
    func handleTapComplete(lesson: Lesson, row: StudentChecklistRowState?) {
        if let cid = row?.contractID, 
           let c = vm.fetchContract(by: cid, modelContext: modelContext), 
           c.status != .complete {
            c.status = .complete
            c.completedAt = AppCalendar.startOfDay(Date())
            _ = saveCoordinator.save(modelContext, reason: "Complete contract from checklist")
            checklistVM.recompute(for: vm.lessons, using: modelContext)
        } else if (row?.isPresented ?? false) && row?.contractID == nil {
            if let c = vm.ensureContract(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                c.status = .complete
                c.completedAt = AppCalendar.startOfDay(Date())
                _ = saveCoordinator.save(modelContext, reason: "Create-and-complete contract from checklist")
                checklistVM.recompute(for: vm.lessons, using: modelContext)
            }
        }
    }
}

