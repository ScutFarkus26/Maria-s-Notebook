//
//  LogObservationIntent.swift
//  Cosmic Daybook
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
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

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

        let context = try await AppBootstrapping.sharedCoreDataStackForIntent().viewContext

        // A child who has left only when no one in the class has her name.
        try await preferChildInClass(in: context)

        // Confirm the student still exists (could have been removed/synced away).
        guard let cdStudent = context.object(CDStudent.self, id: student.id),
              let studentID = cdStudent.id else {
            throw LogObservationError.studentNotFound(student.fullName)
        }

        // The system presents the resolved student and text for review before
        // any classroom record is written.
        try await requestConfirmation()

        let note = CDNote(context: context)
        note.createdAt = Date()
        note.body = trimmed
        note.scope = .student(studentID)
        note.syncStudentLinks(in: context)

        guard context.safeSave() else { throw LogObservationError.saveFailed }

        Logger.notes.info("Logged observation via Siri for student \(studentID.uuidString, privacy: .public)")
        // The short name, so the two Ettys are told apart ("Etty D").
        return .result(dialog: "Saved your observation about \(cdStudent.shortName).")
    }

    /// Siri's name matching looks through children who have left before any
    /// current child whose name only sounds alike, which keeps "Mark Leah
    /// here" from marking Lea. A note is different: filed on Leah, who has
    /// left, it is lost to the class, while Lea is who the guide almost
    /// certainly meant (bug hunt 2026-10-29, #20). So when the child Siri
    /// found has left and children in the class have her name, or one that
    /// sounds just like it, one of them is taken instead, and Siri asks which
    /// when there are several. The parameter is set to her, so the
    /// confirmation that follows names her.
    @MainActor
    private func preferChildInClass(in context: NSManagedObjectContext) async throws {
        let current = StudentEntityQuery.entities(SiriHost.roster(in: context))
        let stayIns = Self.currentChildren(
            for: student.matcherCandidate, among: current.map(\.matcherCandidate)
        )
        let candidates = current.filter { entity in stayIns.contains { $0.id == entity.id } }
        switch candidates.count {
        case 0:
            return
        case 1:
            student = candidates[0]
        default:
            student = try await $student.requestDisambiguation(
                among: candidates, dialog: "Which child did you mean?"
            )
        }
    }

    /// The children in the class (`current`) a note meant for `found` should
    /// go to instead: none while she is in the class herself, otherwise those
    /// whose first name or nickname is hers or sounds just like it (Lea for
    /// Leah, Etty for Eddie: `StudentNameMatcher.soundFolded`, then
    /// `soundKey`). A name only near hers is a guess and doesn't count.
    nonisolated static func currentChildren(
        for found: StudentNameMatcher.Candidate, among current: [StudentNameMatcher.Candidate]
    ) -> [StudentNameMatcher.Candidate] {
        guard !current.contains(where: { $0.id == found.id }) else { return [] }
        func sounds(_ name: String) -> String {
            StudentNameMatcher.soundKey(StudentNameMatcher.soundFolded(name))
        }
        func givenNames(_ candidate: StudentNameMatcher.Candidate) -> [String] {
            [candidate.firstName, candidate.nickname ?? ""].map(sounds).filter { !$0.isEmpty }
        }
        let hers = Set(givenNames(found))
        return current.filter { !hers.isDisjoint(with: givenNames($0)) }
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
            return "Something went wrong saving the observation. Try again."
        }
    }
}
