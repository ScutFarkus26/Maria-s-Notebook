import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The presentation, work and Today errors are shown as they are (alerts,
/// toasts, MCP results), so each must read as a plain sentence: no raw
/// system text, no "(While: …)", no status codes or type names. And
/// `PresentationFailureMessage` shows those sentences but never a raw error.
@Suite("Presentation and work failure messages")
@MainActor
struct PresentationFailureMessageTests {

    private static let typedErrors: [any LocalizedError] = [
        PresentationRecorder.RecordError.nobodyPresent,
        PresentationRecorder.RecordError.missingLesson,
        PresentationRecorder.RecordError.saveFailed,
        ImmediatePresentationRecordingService.RecordingError.invalidAssignment,
        ImmediatePresentationRecordingService.RecordingError.recordingFailed,
        ImmediatePresentationRecordingService.RecordingError.saveFailed,
        ImmediatePresentationRecordingService.RecordingError.undoUnavailable,
        ImmediatePresentationRecordingService.RecordingError.undoSaveFailed,
        PresentationSessionCommit.CommitError.missingIdentity,
        PresentationSessionCommit.CommitError.saveFailed,
        PresentationOutcomePersistenceService.PersistenceError.missingPresentationID,
        PresentationOutcomePersistenceService.PersistenceError.presentationNotFound(UUID()),
        WorkLogService.LogError.nothingToLog,
        WorkLogService.LogError.saveFailed,
        WorkLogService.LogError.undoSaveFailed,
        WorkLogService.LogError.undoUnavailable,
        WorkDeletionService.ServiceError.studentNotOnWork,
        WorkDeletionService.ServiceError.wouldEmptyRow,
        WorkDeletionService.ServiceError.saveFailed,
        WorkRepository.AssignmentError.studentNotEnrolled(name: "Naomi Levin", status: "withdrawn"),
        TodayAbsentMover.MoveError.saveFailed,
        TodayAbsentMover.MoveError.undoSaveFailed,
        TodayAbsentMover.MoveError.undoUnavailable,
        RolloverService.ApplyError.saveFailed,
        StudentDocumentFileStorage.StudentDocumentError.sourceMissing,
        StudentDocumentFileStorage.StudentDocumentError.writeFailed(
            underlying: CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: "/Users/x/Student Files"])
        ),
        StudentCSVImporter.ImportError.cantOpen,
        StudentCSVImporter.ImportError.unreadableText,
        StudentCSVImporter.ImportError.needsMapping
    ]

    /// Words and marks that only ever come from raw errors or developer labels.
    private static let rawMarkers = [
        "While:", "NSCocoaErrorDomain", "Error Domain", "code=", "(error", "CD", "Entity",
        "/Users", "Student Files", "could not", "cannot", "withdrawn", "Please"
    ]

    @Test("Every typed description is a plain sentence")
    func typedDescriptionsArePlain() throws {
        for error in Self.typedErrors {
            let text = try #require(error.errorDescription, "\(error) has no description")
            #expect(!text.isEmpty)
            #expect(text.hasSuffix(".") || text.hasSuffix("?"), "not a sentence: \(text)")
            for marker in Self.rawMarkers {
                #expect(!text.contains(marker), "\(error) says \"\(marker)\": \(text)")
            }
        }
    }

    @Test("A departed child's refusal names them without the status word")
    func departedChildRefusal() {
        let error = WorkRepository.AssignmentError.studentNotEnrolled(name: "Naomi Levin", status: "transferred")
        #expect(error.errorDescription == "Naomi Levin has left the class, so they can't get new work.")
    }

    @Test("The app's own errors speak for themselves")
    func typedErrorsPassThrough() {
        let message = PresentationFailureMessage.message(
            for: WorkLogService.LogError.saveFailed, fallback: "fallback"
        )
        #expect(message == "Couldn't save that work check. Try again.")
        #expect(PresentationFailureMessage.message(
            for: PresentationRecorder.RecordError.nobodyPresent, fallback: "fallback"
        ) == "Choose at least one child who was there before recording this presentation.")
    }

    @Test("A raw system error gets the screen's fallback, never its own text")
    func rawErrorsGetTheFallback() {
        let fallback = "Couldn't record the presentation. Nothing was changed. Try again."
        let coreData = NSError(
            domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed. (Cocoa error 1570.)"]
        )
        #expect(PresentationFailureMessage.message(for: coreData, fallback: fallback) == fallback)

        struct SomeLibraryError: LocalizedError {
            var errorDescription: String? { "kCFErrorDomainCFNetwork -1005" }
        }
        #expect(PresentationFailureMessage.message(for: SomeLibraryError(), fallback: fallback) == fallback)
        #expect(PresentationFailureMessage.plainDescription(of: SomeLibraryError()) == nil)
    }
}
