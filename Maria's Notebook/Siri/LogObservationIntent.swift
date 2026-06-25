//
//  LogObservationIntent.swift
//  Maria's Notebook
//
//  Lets a teacher record an observation about a student by voice or from the
//  Shortcuts app — without opening the app. Mirrors the note-creation path used
//  by QuickNoteViewModel (scope + student links) so the data is identical.
//

import AppIntents
import CoreData
import OSLog

struct LogObservationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Observation"
    static let description = IntentDescription(
        "Record an observation note about a student.",
        categoryName: "Observations"
    )

    /// Run in the background so the observation is saved without launching the UI.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Student")
    var student: StudentEntity

    @Parameter(
        title: "Observation",
        requestValueDialog: "What did you observe?"
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log observation about \(\.$student): \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LogObservationError.emptyText }

        let context = AppBootstrapping.getSharedCoreDataStack().viewContext

        // Confirm the student still exists (could have been removed/synced away).
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id == %@", student.id as CVarArg)
        request.fetchLimit = 1
        guard let cdStudent = context.safeFetchFirst(request),
              let studentID = cdStudent.id else {
            throw LogObservationError.studentNotFound(student.fullName)
        }

        let note = CDNote(context: context)
        note.createdAt = Date()
        note.body = trimmed
        note.scope = .student(studentID)
        note.syncStudentLinks(in: context)

        guard context.safeSave() else { throw LogObservationError.saveFailed }

        Logger.notes.info("Logged observation via Siri for student \(studentID.uuidString, privacy: .public)")
        return .result(dialog: "Saved your observation about \(cdStudent.firstName).")
    }
}

// MARK: - Errors

/// User-facing errors. Conforming to `CustomLocalizedStringResourceConvertible`
/// means Siri speaks/shows a real sentence instead of a generic failure.
enum LogObservationError: Error, CustomLocalizedStringResourceConvertible {
    case emptyText
    case studentNotFound(String)
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyText:
            return "The observation was empty, so nothing was saved."
        case .studentNotFound(let name):
            return "I couldn't find \(name) in your students."
        case .saveFailed:
            return "Something went wrong saving the observation. Please try again."
        }
    }
}
