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
    static func commitLessons(
        parsed: LessonCSVImporter.Parsed, into context: NSManagedObjectContext,
        existingLessons: [Lesson]
    ) throws -> ImportCommitResult {
        let inserted = try LessonCSVImporter.commit(
            parsed: parsed, into: context, existingLessons: existingLessons
        )
        var message = "Imported \(inserted) row(s)."
        if !parsed.potentialDuplicates.isEmpty {
            let firstFew = parsed.potentialDuplicates.prefix(5).joined(separator: "\n• ")
            message += "\n\nPotential duplicates detected: \(parsed.potentialDuplicates.count)."
            if !firstFew.isEmpty {
                message += "\n\nExamples:\n• \(firstFew)"
            }
        }
        if !parsed.warnings.isEmpty {
            message += "\n\nWarnings:\n" + parsed.warnings.joined(separator: "\n")
        }
        return ImportCommitResult(title: "CSV Import Complete", message: message)
    }

    @MainActor
    static func commitStudents(
        parsed: StudentCSVImporter.Parsed, into context: NSManagedObjectContext,
        existingStudents: [Student]
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
