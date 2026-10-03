import Foundation
import CoreData
import OSLog

/// Handles CSV import operations for students, providing static methods
/// to process file imports, mapping confirmations, and import commits.
///
/// This extracts the CSV import handling logic from StudentsView for better
/// testability and separation of concerns.
enum StudentsCSVImportHandler {
    private static let logger = Logger.students
    static let failureTitle = "Couldn't Import Students"
    static let commitFailureMessage = "Couldn't add the students. Nothing was imported. Try again."

    /// The alert for a file that couldn't be read: the importer's own plain
    /// sentence, or the shared file wording for anything else. The raw error
    /// goes to the log.
    static func failureAlert(for error: Error) -> ImportAlert {
        logger.error("Student import failed: \(error, privacy: .public)")
        let message = (error as? StudentCSVImporter.ImportError)?.errorDescription
            ?? AppErrorMessages.importMessage(for: error, fileType: "spreadsheet")
        return ImportAlert(title: failureTitle, message: message)
    }

    /// Alert model for displaying import results or errors
    struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Result of the file import operation containing the task and any immediate error
    struct FileImportResult {
        let task: Task<Void, Never>?
        let immediateError: ImportAlert?
    }

    /// Handle initial file selection and start header scanning.
    ///
    /// - Parameters:
    ///   - result: The result from the file importer
    ///   - existingTask: Reference to any existing parsing task to cancel
    ///   - onHeadersScanned: Called when headers are successfully scanned with (headers, suggestedMapping, fileURL)
    ///   - onError: Called with an ImportAlert when an error occurs
    ///   - onFinally: Called when the operation completes (success or failure)
    /// - Returns: FileImportResult containing the new task (if started) or an immediate error
    static func handleFileImport(
        _ result: Result<URL, Error>,
        cancellingTask existingTask: Task<Void, Never>?,
        onHeadersScanned: @MainActor @Sendable @escaping (
            _ headers: [String], _ mapping: StudentCSVImporter.Mapping, _ fileURL: URL
        ) -> Void,
        onError: @MainActor @Sendable @escaping (ImportAlert) -> Void,
        onFinally: @MainActor @Sendable @escaping () -> Void
    ) -> FileImportResult {
        existingTask?.cancel()

        do {
            let url = try result.get()
            let task = StudentsImportCoordinator.startHeaderScan(
                from: url,
                onParsed: { headers, mapping in
                    onHeadersScanned(headers, mapping, url)
                },
                onError: { error in
                    onError(failureAlert(for: error))
                },
                onFinally: onFinally
            )
            return FileImportResult(task: task, immediateError: nil)
        } catch {
            onFinally()
            return FileImportResult(task: nil, immediateError: failureAlert(for: error))
        }
    }

    // Handle mapping confirmation and start parsing with the confirmed mapping.
    //
    // - Parameters:
    //   - mapping: The confirmed column mapping
    //   - fileURL: The URL of the file to parse
    //   - students: Existing students for duplicate detection
    //   - existingTask: Reference to any existing parsing task to cancel
    //   - onParsed: Called when parsing completes successfully
    //   - onError: Called with an ImportAlert when an error occurs
    //   - onFinally: Called when the operation completes (success or failure)
    // - Returns: The new parsing task, or nil if fileURL was nil
    // swiftlint:disable:next function_parameter_count
    static func handleMappingConfirm(
        mapping: StudentCSVImporter.Mapping,
        fileURL: URL?,
        students: [CDStudent],
        cancellingTask existingTask: Task<Void, Never>?,
        onParsed: @MainActor @Sendable @escaping (StudentCSVImporter.Parsed) -> Void,
        onError: @MainActor @Sendable @escaping (ImportAlert) -> Void,
        onFinally: @MainActor @Sendable @escaping () -> Void
    ) -> Task<Void, Never>? {
        guard let fileURL else { return nil }

        existingTask?.cancel()

        return StudentsImportCoordinator.startMappedParse(
            from: fileURL,
            mapping: mapping,
            students: students,
            onParsed: onParsed,
            onError: { error in
                onError(failureAlert(for: error))
            },
            onFinally: onFinally
        )
    }

    /// Handle the final import commit, persisting students to the database.
    ///
    /// - Parameters:
    ///   - parsed: The parsed import data to commit
    ///   - viewContext: The model context for database operations
    ///   - existingStudents: Existing students for duplicate detection
    /// - Returns: An ImportAlert with the result (success or failure)
    static func handleImportCommit(
        _ parsed: StudentCSVImporter.Parsed,
        viewContext: NSManagedObjectContext,
        existingStudents: [CDStudent]
    ) -> ImportAlert {
        do {
            let result = try ImportCommitService.commitStudents(
                parsed: parsed,
                into: viewContext,
                existingStudents: existingStudents
            )
            return ImportAlert(title: result.title, message: result.message)
        } catch {
            // The save failed, so drop the half-made students: "Nothing was
            // imported" has to be true.
            logger.error("Student import save failed: \(error, privacy: .public)")
            viewContext.rollback()
            return ImportAlert(title: failureTitle, message: commitFailureMessage)
        }
    }
}
