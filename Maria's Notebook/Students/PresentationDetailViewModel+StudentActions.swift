// PresentationDetailViewModel+StudentActions.swift
// Move-students, needs-another-presentation, and schedule-next-lesson actions.

import Foundation
import SwiftData

extension PresentationDetailViewModel {

    // MARK: - Move Students

    /// Handles the "Move Students" action, creating a new lesson for them and removing them from this one
    func moveStudentsToInbox(
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard !studentsToMove.isEmpty, let currentLesson = lessonObject(from: lessons) else { return }

        let actions = PresentationDetailActions()

        // Perform move using helper
        self.movedStudentNames = actions.moveStudentsToInbox(
            currentLesson: currentLesson,
            studentsToMove: studentsToMove,
            studentsAll: studentsAll,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: modelContext
        )

        // Remove students from current VM state
        selectedStudentIDs.subtract(studentsToMove)

        // Sync to model immediately so the view updates
        let remainingUUIDs = Set(lessonAssignment.resolvedStudentIDs).subtracting(studentsToMove)
        lessonAssignment.studentIDs = remainingUUIDs.map(\.uuidString)
        lessonAssignment.students = studentsAll.filter { remainingUUIDs.contains($0.id) }
        saveCoordinator.save(modelContext, reason: "Moving students to inbox")

        PresentationDetailUtilities.notifyInboxRefresh()

        // UI Updates
        studentsToMove.removeAll()
        showMovedBanner = true

        // Hide banner after delay
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(3))
            showMovedBanner = false
        }
    }

    // MARK: - Needs Another Presentation

    /// Reacts to changes in "Needs Another Presentation" toggle
    func handleNeedsAnotherChange(
        newValue: Bool,
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard newValue else { return }
        guard !selectedStudentIDs.isEmpty else { return }

        // If toggled ON, ensure we create a fresh draft entry if one doesn't exist
        let sameStudents = Set(selectedStudentIDs)
        let exists = lessonAssignmentsAll.contains { la in
            la.resolvedLessonID == editingLessonID &&
            la.scheduledFor == nil &&
            !la.isPresented &&
            Set(la.resolvedStudentIDs) == sameStudents
        }

        if !exists {
            let newLA = PresentationFactory.makeDraft(
                lessonID: editingLessonID,
                studentIDs: Array(sameStudents)
            )
            PresentationFactory.attachRelationships(
                to: newLA,
                lesson: nil,
                students: studentsAll.filter { sameStudents.contains($0.id) }
            )
            modelContext.insert(newLA)
        }
    }

    // MARK: - Schedule Next Lesson

    /// Schedules a new presentation for the next lesson in the group
    func scheduleNextLessonToInbox(
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard let next = nextLessonInGroup(from: lessons) else { return }
        guard !selectedStudentIDs.isEmpty else { return }

        let sameStudents = Set(selectedStudentIDs)

        // Avoid duplicates
        let exists = lessonAssignmentsAll.contains { la in
            la.resolvedLessonID == next.id && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
        }
        if exists { return }

        let newLA = PresentationFactory.makeDraft(
            lessonID: next.id,
            studentIDs: Array(sameStudents)
        )
        PresentationFactory.attachRelationships(
            to: newLA,
            lesson: nil,
            students: studentsAll.filter { sameStudents.contains($0.id) }
        )
        modelContext.insert(newLA)
        saveCoordinator.save(modelContext, reason: "Scheduling next lesson")
        PresentationDetailUtilities.notifyInboxRefresh()
    }
}
