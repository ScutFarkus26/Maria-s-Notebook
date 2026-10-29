// PresentationDetailViewModel+StudentActions.swift
// Move-students, needs-another-presentation, and schedule-next-lesson actions.

import Foundation

extension PresentationDetailViewModel {

    // MARK: - Move Students

    /// The lesson a split puts the children on, which the split sheet names.
    func splitLesson(from lessons: [CDLesson]) -> CDLesson? {
        PresentationDetailActions.splitLesson(
            for: lessonAssignment, edited: lessonObject(from: lessons), lessons: lessons
        )
    }

    /// Splits `studentsToMove` off onto a plan of their own and saves at once,
    /// then shows the banner with its Undo for a few seconds.
    func moveStudentsToInbox(
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        lessons: [CDLesson]
    ) {
        guard !studentsToMove.isEmpty, let lesson = splitLesson(from: lessons) else { return }

        let split = PresentationDetailActions().moveStudentsToInbox(
            from: lessonAssignment,
            currentLesson: lesson,
            studentsToMove: studentsToMove,
            studentsAll: studentsAll,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: viewContext
        )
        selectedStudentIDs.subtract(studentsToMove)
        studentsToMove.removeAll()
        saveCoordinator.save(viewContext, reason: "Splitting children off to their own group")
        PresentationDetailUtilities.notifyInboxRefresh()

        lastSplit = split
        splitBannerTask?.cancel()
        splitBannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.lastSplit = nil
        }
    }

    /// Takes the last split back: the children return to this presentation.
    func undoLastSplit() {
        guard let split = lastSplit else { return }
        splitBannerTask?.cancel()
        lastSplit = nil
        guard PresentationDetailActions().undoSplit(split, context: viewContext) else { return }
        selectedStudentIDs.formUnion(split.studentIDs)
        saveCoordinator.save(viewContext, reason: "Undoing a split")
        PresentationDetailUtilities.notifyInboxRefresh()
    }
}
