import SwiftUI
import OSLog
import CoreData

// MARK: - Completion & Computed Helpers

extension UnifiedPresentationWorkflowPanel {

    // MARK: - Computed Properties

    /// Existing work items for this lesson and these students
    func existingWorkItems(for studentID: UUID) -> [CDWorkModel] {
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString
        return allWorkModels.filter { work in
            work.studentID == studentIDString && work.lessonID == lessonIDString
        }
    }

    var canComplete: Bool {
        // Must have valid presentation status
        presentationViewModel.canDismiss
    }

    // Progress tracking
    var studentsWithNotes: Int {
        presentationViewModel.entries.values.filter { !$0.observation.isEmpty }.count
    }

    var studentsWithUnderstanding: Int {
        presentationViewModel.entries.values.filter { $0.understandingLevel != 3 }.count
    }

    var hasGroupObservation: Bool {
        !presentationViewModel.groupObservation.isEmpty
    }

    // MARK: - Completion

    func completeWorkflow() {
        isSaving = true

        // 1. Unlock next lessons if needed
        presentationViewModel.unlockNextLessonsIfNeeded(
            lessonID: lessonID,
            viewContext: viewContext,
            lessons: Array(lessons),
            lessonAssignments: Array(lessonAssignments)
        )

        // 2. Create work items
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        let repository = WorkRepository(context: cdContext)

        for (studentID, drafts) in workDrafts {
            for draft in drafts where !draft.title.isEmpty {

                do {
                    let work = try repository.createWork(
                        studentID: studentID,
                        lessonID: lessonID,
                        title: draft.title,
                        kind: draft.kind,
                        scheduledDate: draft.dueDate
                    )

                    // Update status, notes, check-in style, and completion details after creation
                    work.status = draft.status
                    work.checkInStyle = draft.checkInStyle

                    // Combine notes and completion note if present
                    var allNotes = draft.notes
                    if draft.status == .complete && !draft.completionNote.isEmpty {
                        if !allNotes.isEmpty {
                            allNotes += "\n\nCompletion: " + draft.completionNote
                        } else {
                            allNotes = "Completion: " + draft.completionNote
                        }
                    }
                    if !allNotes.isEmpty {
                        work.setLegacyNoteText(allNotes, in: cdContext)
                    }

                    // Set completion outcome if status is complete
                    if draft.status == .complete, let outcome = draft.completionOutcome {
                        work.completionOutcome = outcome
                    }
                } catch {
                    Self.logger.warning("Failed to create work item: \(error)")
                }
            }
        }

        // 3. Execute next lesson action
        presentationViewModel.executeNextLessonAction(
            studentIDs: Set(students.compactMap(\.id)),
            allStudents: students,
            allLessons: Array(lessons),
            lessonAssignments: Array(lessonAssignments),
            viewContext: viewContext
        )

        // 4. Save everything
        saveCoordinator.save(viewContext, reason: "Unified Presentation Workflow")

        onComplete()
    }
}
