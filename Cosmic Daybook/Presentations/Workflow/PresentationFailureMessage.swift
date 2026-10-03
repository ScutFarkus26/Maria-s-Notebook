// PresentationFailureMessage.swift
// The sentence a presentation or work screen shows when recording, undoing,
// logging or saving fails.

import Foundation
import OSLog

/// The app's own presentation and work errors are written as plain sentences
/// for the screen, so they speak for themselves; anything else (a Core Data
/// error, a file error) gets the screen's `fallback`, never its raw text. The
/// raw error goes to the log.
enum PresentationFailureMessage {
    private static let logger = Logger.presentations

    static func message(for error: Error, fallback: String) -> String {
        logger.error("Showing a failure: \(error, privacy: .public)")
        return plainDescription(of: error) ?? fallback
    }

    /// The description of one of the errors whose wording is written for the
    /// screen, or nil for anything else.
    static func plainDescription(of error: Error) -> String? {
        let description: String?
        switch error {
        case let typed as PresentationRecorder.RecordError: description = typed.errorDescription
        case let typed as ImmediatePresentationRecordingService.RecordingError: description = typed.errorDescription
        case let typed as PresentationSessionCommit.CommitError: description = typed.errorDescription
        case let typed as PresentationOutcomePersistenceService.PersistenceError: description = typed.errorDescription
        case let typed as WorkLogService.LogError: description = typed.errorDescription
        case let typed as WorkDeletionService.ServiceError: description = typed.errorDescription
        case let typed as WorkRepository.AssignmentError: description = typed.errorDescription
        case let typed as TodayAbsentMover.MoveError: description = typed.errorDescription
        default: description = nil
        }
        guard let description, !description.isEmpty else { return nil }
        return description
    }
}
