// PresentationDetailViewModel+StudentActions.swift
// Move-students, needs-another-presentation, and schedule-next-lesson actions.

import Foundation

extension PresentationDetailViewModel {

    // MARK: - Move Students

    /// Handles the "Move Students" action, creating a new lesson for them and removing them from this one
    func moveStudentsToInbox(
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        lessons: [CDLesson]
    ) {
        guard !studentsToMove.isEmpty, let currentLesson = lessonObject(from: lessons) else { return }

        let actions = PresentationDetailActions()

        // Perform move using helper
        self.movedStudentNames = actions.moveStudentsToInbox(
            currentLesson: currentLesson,
            studentsToMove: studentsToMove,
            studentsAll: studentsAll,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: viewContext
        )

        // Remove students from current VM state
        selectedStudentIDs.subtract(studentsToMove)

        // Sync to model immediately so the view updates
        let remainingUUIDs = Set(lessonAssignment.resolvedStudentIDs).subtracting(studentsToMove)
        lessonAssignment.studentIDs = remainingUUIDs.map(\.uuidString)
        saveCoordinator.save(viewContext, reason: "Moving students to inbox")

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
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        lessons: [CDLesson]
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
            _ = PresentationFactory.makeDraft(
                lessonID: editingLessonID,
                studentIDs: Array(sameStudents),
                context: viewContext
            )
        }
    }

}
