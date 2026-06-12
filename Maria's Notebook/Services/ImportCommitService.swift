import Foundation
import CoreData

public struct ImportCommitResult {
    public let title: String
    public let message: String
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public enum ImportCommitService {

    // MARK: - Core Data API

    @MainActor
    static func commitStudents(
        parsed: StudentCSVImporter.Parsed, into context: NSManagedObjectContext,
        existingStudents: [CDStudent]
    ) throws -> ImportCommitResult {
        let summary = try StudentCSVImporter.commit(
            parsed: parsed, into: context, existingStudents: existingStudents
        )
        var message = "Imported \(summary.insertedCount) new and updated \(summary.updatedCount) existing student(s)."
        if !summary.potentialDuplicates.isEmpty {
            let firstFew = summary.potentialDuplicates.prefix(5).joined(separator: "\n• ")
            message += "\n\nPotential duplicates detected: \(summary.potentialDuplicates.count)."
            if !firstFew.isEmpty { message += "\n\nExamples:\n• \(firstFew)" }
        }
        if !summary.warnings.isEmpty {
            message += "\n\nWarnings:\n" + summary.warnings.joined(separator: "\n")
        }
        return ImportCommitResult(title: "CSV Import Complete", message: message)
    }

    // Deprecated SwiftData commit methods removed - no longer needed with Core Data.
}
