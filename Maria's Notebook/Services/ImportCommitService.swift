import Foundation
import CoreData
import SwiftData

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
    // Note: CSV importers still use ModelContext (SwiftData). The context parameter here
    // signals intent; internally we use the shared ModelContainer since both see the same store.

    @MainActor
    static func commitLessons(
        parsed: LessonCSVImporter.Parsed, into context: NSManagedObjectContext,
        existingLessons: [Lesson]
    ) throws -> ImportCommitResult {
        let modelContext = AppBootstrapping.getSharedModelContainer().mainContext
        let inserted = try LessonCSVImporter.commit(
            parsed: parsed, into: modelContext, existingLessons: existingLessons
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
        let modelContext = AppBootstrapping.getSharedModelContainer().mainContext
        let summary = try StudentCSVImporter.commit(
            parsed: parsed, into: modelContext, existingStudents: existingStudents
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

    // MARK: - Deprecated SwiftData Methods

    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func commitLessons(
        parsed: LessonCSVImporter.Parsed, into context: ModelContext,
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

    @available(*, deprecated, message: "Use Core Data overload")
    @MainActor
    static func commitStudents(
        parsed: StudentCSVImporter.Parsed, into context: ModelContext,
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
}
