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
            work.studentID == studentIDString
                && work.lessonID == lessonIDString
                && work.presentationID == presentationID?.uuidString
        }
    }

    // MARK: - Completion

    func completeWorkflow() {
        guard !isSaving else { return }
        isSaving = true

        guard let presentationID else {
            isSaving = false
            saveErrorMessage = PresentationOutcomePersistenceService.PersistenceError
                .missingPresentationID.localizedDescription
            return
        }

        do {
            try PresentationOutcomePersistenceService.persistObservations(
                groupObservation: presentationViewModel.groupObservation,
                studentObservations: presentationViewModel.entries.mapValues(\.observation),
                studentIDs: students.compactMap(\.id),
                presentationID: presentationID,
                context: viewContext
            )
        } catch {
            isSaving = false
            saveErrorMessage = error.localizedDescription
            return
        }

        // 1. Unlock next lessons if needed
        presentationViewModel.unlockNextLessonsIfNeeded(
            lessonID: lessonID,
            viewContext: viewContext,
            lessons: Array(lessons),
            lessonAssignments: Array(lessonAssignments)
        )

        // 2. Create work items
        let repository = WorkRepository(context: viewContext)

        for (studentID, drafts) in presentationViewModel.workDrafts {
            for draft in drafts where !draft.title.trimmed().isEmpty {
                do {
                    let work = try repository.createWork(
                        studentID: studentID,
                        lessonID: lessonID,
                        title: draft.title.trimmed(),
                        kind: draft.kind,
                        presentationID: presentationID,
                        scheduledDate: draft.dueDate,
                        saveImmediately: false
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
                        work.setLegacyNoteText(allNotes, in: viewContext)
                    }

                    // Set completion outcome if status is complete
                    if draft.status == .complete, let outcome = draft.completionOutcome {
                        work.completionOutcome = outcome
                    }

                    // Honor the draft's scheduled check-in date. Previously the
                    // date set in the workflow's DatePicker was silently dropped
                    // (no CDWorkCheckIn was created), so it never appeared on the
                    // work calendar or factored into aging. Skip when the work is
                    // already complete — a scheduled check-in there is moot.
                    if let checkInDate = draft.checkInDate, draft.status != .complete {
                        try WorkCheckInService(context: viewContext)
                            .createCheckIn(for: work, date: checkInDate)
                    }
                } catch {
                    Self.logger.warning("Failed to create work item: \(error)")
                }
            }
        }

        // 3. Persist per-student proficiency confirmations.
        // This is the single common choke point for every entry path (embedded
        // three-panel view AND the LessonAssignmentDetailSheet -> sheet path), so
        // the teacher's "Ready for next lesson" toggles always reach the assignment.
        // confirmStudent is idempotent, so the embedded path's handleWorkflowComplete
        // calling it again will not double-add.
        persistConfirmations()

        // 4. Execute next lesson action
        presentationViewModel.executeNextLessonAction(
            studentIDs: Set(students.compactMap(\.id)),
            allStudents: students,
            allLessons: Array(lessons),
            lessonAssignments: Array(lessonAssignments),
            viewContext: viewContext
        )

        // 5. Save everything. Keep the workflow open when persistence fails so
        // the guide can retry and the UI never reports completion for records
        // that did not reach the store.
        guard saveCoordinator.save(viewContext, reason: "Unified Presentation Workflow") else {
            isSaving = false
            saveErrorMessage = saveCoordinator.lastSaveErrorMessage
                ?? "The presentation could not be saved. Review the records and try again."
            return
        }

        onComplete()
    }

    /// Writes the teacher's in-memory proficiency confirmations onto the lesson's
    /// assignment so BlockingAlgorithmEngine can unblock the next lesson. Mirrors the
    /// canonical persistence in PresentationDetailView+Workflow.handleWorkflowComplete.
    private func persistConfirmations() {
        guard presentationViewModel.requiresConfirmation,
              !presentationViewModel.confirmedStudentIDs.isEmpty else { return }

        // Confirm each student on the assignment for THIS lesson that actually contains
        // them. Matching per-student (rather than requiring the assignment's student-set to
        // exactly equal the visible panel roster) keeps confirmations robust when the roster
        // has been filtered — e.g. a withdrawn or hidden student still in the group, or a
        // single-student sheet derived from a multi-student assignment.
        for studentID in presentationViewModel.confirmedStudentIDs {
            let candidates = lessonAssignments.filter { la in
                la.lessonIDUUID == lessonID && la.studentUUIDs.contains(studentID)
            }
            // Prefer the presented assignment if multiple states exist for the student.
            guard let assignment = candidates.first(where: { $0.isPresented }) ?? candidates.first else {
                continue
            }
            assignment.confirmStudent(studentID)
            ReadinessAutoUnlockService.checkAndUnlock(
                afterConfirmationOn: lessonID,
                studentID: studentID,
                context: viewContext
            )
        }
    }
}
