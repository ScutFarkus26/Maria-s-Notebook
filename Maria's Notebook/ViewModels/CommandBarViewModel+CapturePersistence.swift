import CoreData
import Foundation

@MainActor
extension CommandBarViewModel {
    /// Persists the reviewed proposal as one confirmed operation. Parsing never
    /// calls this method; only the review screen's save button does.
    @discardableResult
    func saveCaptureProposal(
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        presentedAt: Date = Date(),
        recordedPresentationID: UUID? = nil
    ) throws -> CaptureSaveReceipt {
        guard let proposal = captureProposal else {
            throw CaptureSaveError.invalid("There is no capture to save.")
        }
        if let validationMessage = captureValidationMessage {
            throw CaptureSaveError.invalid(validationMessage)
        }

        let studentIDs = proposal.studentIDs
        let students = try fetchStudents(ids: studentIDs, context: context)
        guard students.count == Set(studentIDs).count else {
            throw CaptureSaveError.invalid(
                "One of the selected children is no longer in the roster. Review the capture and try again."
            )
        }

        let receipt = try performAtomicCaptureSave(
            context: context,
            saveCoordinator: saveCoordinator
        ) {
            try persistCapture(
                proposal,
                students: students,
                presentedAt: presentedAt,
                recordedPresentationID: recordedPresentationID,
                context: context
            )
        }
        addToRecent(proposal.rawText)
        return receipt
    }

    private func performAtomicCaptureSave<Result>(
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        changes: () throws -> Result
    ) throws -> Result {
        // A shared view context can contain unrelated edits. A temporary undo
        // manager records only the mutations made by this reviewed capture.
        context.processPendingChanges()
        let previousUndoManager = context.undoManager
        let operationUndoManager = UndoManager()
        operationUndoManager.groupsByEvent = false
        context.undoManager = operationUndoManager
        operationUndoManager.beginUndoGrouping()
        var groupingIsOpen = true

        defer { context.undoManager = previousUndoManager }

        do {
            let result = try changes()
            context.processPendingChanges()
            operationUndoManager.endUndoGrouping()
            groupingIsOpen = false

            guard saveCoordinator.save(context, reason: "saving the reviewed classroom capture") else {
                let message = saveCoordinator.lastSaveErrorMessage
                    ?? "The classroom capture could not be saved."
                throw CaptureSaveError.saveFailed(message)
            }
            return result
        } catch {
            if groupingIsOpen {
                context.processPendingChanges()
                operationUndoManager.endUndoGrouping()
            }
            if operationUndoManager.canUndo {
                operationUndoManager.undo()
                context.processPendingChanges()
            }
            throw error
        }
    }

    private func persistCapture(
        _ proposal: CaptureProposal,
        students: [CDStudent],
        presentedAt: Date,
        recordedPresentationID: UUID?,
        context: NSManagedObjectContext
    ) throws -> CaptureSaveReceipt {
        guard proposal.recordsPresentation else {
            let notes = makeStandaloneObservationNotes(proposal: proposal, context: context)
            return CaptureSaveReceipt(presentationID: nil, noteCount: notes.count, workCount: 0)
        }

        return try persistPresentationCapture(
            proposal,
            students: students,
            presentedAt: presentedAt,
            recordedPresentationID: recordedPresentationID,
            context: context
        )
    }

    private func persistPresentationCapture(
        _ proposal: CaptureProposal,
        students: [CDStudent],
        presentedAt: Date,
        recordedPresentationID: UUID?,
        context: NSManagedObjectContext
    ) throws -> CaptureSaveReceipt {
        guard let lessonID = proposal.lessonID,
              let lesson = try fetchLesson(id: lessonID, context: context) else {
            throw CaptureSaveError.invalid("The selected lesson could not be found. Nothing was saved.")
        }

        let assignment = try resolvePresentation(CapturePresentationRequest(
            lesson: lesson,
            studentIDs: proposal.studentIDs,
            students: students,
            presentedAt: presentedAt,
            recordedPresentationID: recordedPresentationID,
            context: context
        ))
        guard let presentationID = assignment.id else {
            throw CaptureSaveError.invalid("The presentation does not have a saved identity. Nothing was saved.")
        }

        let observations = Dictionary(uniqueKeysWithValues: proposal.studentEntries.map {
            ($0.studentID, $0.observation)
        })
        let notes = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: proposal.groupObservation,
            studentObservations: observations,
            studentIDs: proposal.studentIDs,
            presentationID: presentationID,
            context: context
        )
        let persistence = CapturePersistenceContext(
            lessonID: lessonID,
            lessonName: lesson.name,
            presentationID: presentationID,
            context: context
        )
        let workCount = try persistFollowUps(
            proposal.studentEntries,
            assignment: assignment,
            lesson: lesson,
            persistence: persistence
        )

        return CaptureSaveReceipt(
            presentationID: presentationID,
            noteCount: notes.count,
            workCount: workCount
        )
    }

    private func resolvePresentation(
        _ request: CapturePresentationRequest
    ) throws -> CDLessonAssignment {
        guard let lessonID = request.lesson.id else {
            throw CaptureSaveError.invalid("The selected lesson could not be found. Nothing was saved.")
        }
        if let recordedPresentationID = request.recordedPresentationID {
            return try exactRecordedAssignment(
                id: recordedPresentationID,
                lessonID: lessonID,
                studentIDs: request.studentIDs,
                context: request.context
            )
        }

        let assignment = try reusableAssignment(
            lessonID: lessonID,
            studentIDs: request.studentIDs,
            context: request.context
        ) ?? PresentationFactory.makeDraft(
            lesson: request.lesson,
            students: request.students,
            context: request.context
        )
        return try LifecycleService.recordPresentation(
            from: assignment,
            presentedAt: request.presentedAt,
            modelContext: request.context
        )
    }

    private func persistFollowUps(
        _ entries: [StudentCaptureProposal],
        assignment: CDLessonAssignment,
        lesson: CDLesson,
        persistence: CapturePersistenceContext
    ) throws -> Int {
        var workCount = 0
        for entry in entries {
            switch entry.followUp {
            case .none:
                break
            case .continueObserving:
                markObservationForFollowUp(
                    entry: entry,
                    assignment: assignment,
                    context: persistence.context
                )
            case .practice:
                if try createWorkIfNeeded(kind: .practiceLesson, entry: entry, persistence: persistence) {
                    workCount += 1
                }
            case .followUpWork:
                if try createWorkIfNeeded(kind: .followUpAssignment, entry: entry, persistence: persistence) {
                    workCount += 1
                }
            case .represent:
                try createRepresentationIfNeeded(
                    studentID: entry.studentID,
                    lesson: lesson,
                    context: persistence.context
                )
            case .readyForNextLesson:
                assignment.confirmStudent(entry.studentID)
            }
        }
        return workCount
    }
}

private struct CapturePresentationRequest {
    let lesson: CDLesson
    let studentIDs: [UUID]
    let students: [CDStudent]
    let presentedAt: Date
    let recordedPresentationID: UUID?
    let context: NSManagedObjectContext
}

struct CapturePersistenceContext {
    let lessonID: UUID
    let lessonName: String
    let presentationID: UUID
    let context: NSManagedObjectContext
}
