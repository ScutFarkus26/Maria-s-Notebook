//
//  MarkAbsentIntent.swift
//  Maria's Notebook
//
//  Marks a student absent for today — by voice or from Shortcuts, without
//  opening the app. Uses AttendanceRepository's ensureRecord + updateStatus,
//  the same path the Attendance grid uses (so day normalization is correct).
//

import AppIntents
import CoreData
import OSLog

struct MarkAbsentIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Student Absent"
    static let description = IntentDescription(
        "Mark a student absent for today.",
        categoryName: "Attendance"
    )
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$student) absent today")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext

        guard let cdStudent = context.object(CDStudent.self, id: student.id) else {
            throw MarkAbsentError.studentNotFound(student.fullName)
        }

        try await requestConfirmation()

        let repository = AttendanceRepository(context: context)
        guard let record = repository.ensureRecord(forDate: Date(), student: cdStudent),
              let recordID = record.id else {
            throw MarkAbsentError.saveFailed
        }
        repository.updateStatus(id: recordID, status: .absent)

        guard repository.save() else { throw MarkAbsentError.saveFailed }

        Logger.database.info("Marked student absent via Siri \(cdStudent.firstName, privacy: .public)")
        return .result(dialog: "Marked \(cdStudent.firstName) absent today.")
    }
}

// MARK: - Errors

enum MarkAbsentError: Error, CustomLocalizedStringResourceConvertible {
    case studentNotFound(String)
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .studentNotFound(let name):
            return "I couldn't find \(name) in your students."
        case .saveFailed:
            return "Something went wrong updating attendance. Please try again."
        }
    }
}
