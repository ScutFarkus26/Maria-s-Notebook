import CoreData
import Foundation

/// Performs the small, immediate persistence step behind “Just Presented”.
///
/// This service intentionally records only the presentation lifecycle. Observations,
/// follow-up work, and next-lesson planning remain explicit, separate actions.
struct ImmediatePresentationRecordingService {
    enum RecordingError: LocalizedError {
        case invalidAssignment
        case recordingFailed(String)
        case saveFailed(String)
        case undoUnavailable
        case undoSaveFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidAssignment:
                return "This presentation is no longer available. Nothing was recorded."
            case .recordingFailed(let message):
                return "The presentation could not be recorded: \(message)"
            case .saveFailed(let message):
                return message
            case .undoUnavailable:
                return "This presentation can no longer be undone."
            case .undoSaveFailed(let message):
                return message
            }
        }
    }

    /// A short-lived receipt for the Undo action shown after recording.
    ///
    /// The token uses Core Data object identities so repeated presentations of the
    /// same lesson never cause Undo to remove another presentation's history.
    struct UndoToken {
        let assignmentID: UUID
        let presentedDay: Date
        let createdHistoryCount: Int

        let assignmentObjectID: NSManagedObjectID
        let assignmentState: AssignmentStateSnapshot
        let createdHistoryObjectIDs: [NSManagedObjectID]
        let existingHistoryStates: [HistoryStateSnapshot]
        let createdEnrollmentObjectIDs: [NSManagedObjectID]
        let existingEnrollmentStates: [EnrollmentStateSnapshot]
    }

    /// Records one exact assignment as presented and persists the result immediately.
    ///
    /// - Returns: A token suitable for a transient Undo action.
    static func record(
        assignment: CDLessonAssignment,
        presentedOn day: Date,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> UndoToken {
        let preparation = try prepareRecord(assignment: assignment, day: day, context: context)
        let changes = try persistRecord(
            assignment: assignment,
            preparation: preparation,
            context: context,
            saveCoordinator: saveCoordinator
        )
        return makeUndoToken(assignment: assignment, preparation: preparation, changes: changes)
    }

    /// Reverses a successful `record` call without touching older presentation history.
    static func undo(
        _ token: UndoToken,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws {
        let assignment: CDLessonAssignment
        do {
            guard let fetched = try context.existingObject(with: token.assignmentObjectID)
                as? CDLessonAssignment,
                  !fetched.isDeleted,
                  fetched.id == token.assignmentID else {
                throw RecordingError.undoUnavailable
            }
            assignment = fetched
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.undoUnavailable
        }

        try performScopedSave(
            in: context,
            using: saveCoordinator,
            operation: .undo
        ) {
            token.assignmentState.restore(assignment)
            restoreExistingHistory(token, in: context)
            deleteHistoryCreatedByRecord(token, in: context)
            restoreExistingEnrollments(token, in: context)
            deleteEnrollmentsCreatedByRecord(token, in: context)
        }
    }
}

private extension ImmediatePresentationRecordingService {
    static func prepareRecord(
        assignment: CDLessonAssignment,
        day: Date,
        context: NSManagedObjectContext
    ) throws -> RecordPreparation {
        guard assignment.managedObjectContext === context,
              !assignment.isDeleted,
              let assignmentID = assignment.id,
              !assignment.lessonID.isEmpty,
              !assignment.studentIDs.isEmpty else {
            throw RecordingError.invalidAssignment
        }

        let existingRows: [CDLessonPresentation]
        do {
            existingRows = try historyRows(for: assignmentID, in: context)
        } catch {
            throw RecordingError.recordingFailed(error.localizedDescription)
        }
        let enrollments = enrollmentRows(for: Set(assignment.studentIDs), in: context)
        return RecordPreparation(
            assignmentID: assignmentID,
            presentedDay: AppCalendar.startOfDay(day),
            assignmentState: AssignmentStateSnapshot(assignment: assignment),
            existingHistoryIdentities: Set(existingRows.map(ObjectIdentifier.init)),
            priorHistoryStates: existingRows.map {
                HistoryStateBeforeSave(row: $0, lastObservedAt: $0.lastObservedAt)
            },
            existingEnrollmentIdentities: Set(enrollments.map(ObjectIdentifier.init)),
            priorEnrollmentStates: enrollments.map(EnrollmentStateBeforeSave.init)
        )
    }

    static func persistRecord(
        assignment: CDLessonAssignment,
        preparation: RecordPreparation,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> RecordChanges {
        try performScopedSave(in: context, using: saveCoordinator, operation: .record) {
            try applyPresentationLifecycle(
                assignment: assignment,
                presentedDay: preparation.presentedDay,
                context: context
            )
            let trackID = enrollInSequenceTrack(assignment: assignment, context: context)
            return try collectRecordChanges(
                assignment: assignment,
                preparation: preparation,
                trackID: trackID,
                context: context
            )
        }
    }

    static func applyPresentationLifecycle(
        assignment: CDLessonAssignment,
        presentedDay: Date,
        context: NSManagedObjectContext
    ) throws {
        assignment.markPresented(at: presentedDay)
        _ = try LifecycleService.recordPresentation(
            from: assignment,
            presentedAt: presentedDay,
            modelContext: context
        )
        assignment.needsAnotherPresentation = false
    }

    static func enrollInSequenceTrack(
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) -> String? {
        guard let lesson = assignment.lesson else { return nil }
        let area = lesson.area.trimmed()
        let sequence = lesson.sequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty else { return nil }
        return SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: area,
            lessonSequence: sequence,
            studentIDs: assignment.studentIDs,
            context: context,
            saveChanges: false
        )
    }

    static func collectRecordChanges(
        assignment: CDLessonAssignment,
        preparation: RecordPreparation,
        trackID: String?,
        context: NSManagedObjectContext
    ) throws -> RecordChanges {
        let history = try historyRows(for: preparation.assignmentID, in: context)
        let createdHistory = history.filter {
            !preparation.existingHistoryIdentities.contains(ObjectIdentifier($0))
        }
        let enrollments = enrollmentRows(for: Set(assignment.studentIDs), in: context)
        let createdEnrollments = enrollments.filter {
            $0.trackID == trackID
                && !preparation.existingEnrollmentIdentities.contains(ObjectIdentifier($0))
        }
        let existingEnrollmentStates = preparation.priorEnrollmentStates
            .filter { $0.trackID == trackID }
            .map(EnrollmentStateSnapshot.init)
        return RecordChanges(
            createdHistoryRows: createdHistory,
            createdEnrollmentRows: createdEnrollments,
            existingEnrollmentStates: existingEnrollmentStates
        )
    }

    static func makeUndoToken(
        assignment: CDLessonAssignment,
        preparation: RecordPreparation,
        changes: RecordChanges
    ) -> UndoToken {
        UndoToken(
            assignmentID: preparation.assignmentID,
            presentedDay: preparation.presentedDay,
            createdHistoryCount: changes.createdHistoryRows.count,
            assignmentObjectID: assignment.objectID,
            assignmentState: preparation.assignmentState,
            createdHistoryObjectIDs: changes.createdHistoryRows.map(\.objectID),
            existingHistoryStates: preparation.priorHistoryStates.map {
                HistoryStateSnapshot(
                    objectID: $0.row.objectID,
                    lastObservedAt: $0.lastObservedAt,
                    followUpActionRaw: $0.followUpActionRaw,
                    followUpReviewAt: $0.followUpReviewAt,
                    followUpResolvedAt: $0.followUpResolvedAt,
                    followUpResolutionRaw: $0.followUpResolutionRaw,
                    followUpUpdatedAt: $0.followUpUpdatedAt,
                    followUpEvidenceRaw: $0.followUpEvidenceRaw,
                    followUpNote: $0.followUpNote,
                    followUpSupportRaw: $0.followUpSupportRaw
                )
            },
            createdEnrollmentObjectIDs: changes.createdEnrollmentRows.map(\.objectID),
            existingEnrollmentStates: changes.existingEnrollmentStates
        )
    }

    // MARK: - Scoped failure recovery

    private static func performScopedSave<Result>(
        in context: NSManagedObjectContext,
        using saveCoordinator: SaveCoordinator,
        operation: ScopedOperation,
        changes: () throws -> Result
    ) throws -> Result {
        // Flush older notifications with the original manager so this group
        // contains only the changes made by this service call.
        context.processPendingChanges()
        let previousUndoManager = context.undoManager
        let operationUndoManager = makeOperationUndoManager()
        context.undoManager = operationUndoManager
        operationUndoManager.beginUndoGrouping()
        var groupingIsOpen = true
        var operationWasReverted = false

        defer { context.undoManager = previousUndoManager }

        do {
            let result = try changes()
            context.processPendingChanges()
            operationUndoManager.endUndoGrouping()
            groupingIsOpen = false

            guard saveCoordinator.save(context, reason: operation.reason) else {
                revert(operationUndoManager, in: context)
                operationWasReverted = true
                let message = saveCoordinator.lastSaveErrorMessage
                    ?? "The change could not be saved."
                throw operation.saveFailure(message)
            }
            return result
        } catch {
            if groupingIsOpen { operationUndoManager.endUndoGrouping() }
            if !operationWasReverted { revert(operationUndoManager, in: context) }
            if let recordingError = error as? RecordingError { throw recordingError }
            throw operation.operationFailure(error.localizedDescription)
        }
    }

    private enum ScopedOperation {
        case record
        case undo

        var reason: String {
            switch self {
            case .record: "Recording presentation"
            case .undo: "Undoing recorded presentation"
            }
        }

        func saveFailure(_ message: String) -> RecordingError {
            switch self {
            case .record: .saveFailed(message)
            case .undo: .undoSaveFailed(message)
            }
        }

        func operationFailure(_ message: String) -> RecordingError {
            switch self {
            case .record: .recordingFailed(message)
            case .undo: .undoSaveFailed(message)
            }
        }
    }

    private static func makeOperationUndoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    private static func revert(
        _ undoManager: UndoManager,
        in context: NSManagedObjectContext
    ) {
        if undoManager.canUndo {
            undoManager.undo()
        }
        context.processPendingChanges()
    }
}
