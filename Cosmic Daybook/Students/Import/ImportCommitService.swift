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

    static func commitStudents(
        parsed: StudentCSVImporter.Parsed, into context: NSManagedObjectContext,
        existingStudents: [CDStudent]
    ) throws -> ImportCommitResult {
        let summary = try StudentCSVImporter.commit(
            parsed: parsed, into: context, existingStudents: existingStudents
        )
        return ImportCommitResult(title: "Students Imported", message: message(for: summary))
    }

    /// "Added 3 new students and updated 2.", then any children who might
    /// already be in the class, then the lines that were skipped.
    static func message(for summary: StudentCSVImporter.Summary) -> String {
        var message = countsSentence(inserted: summary.insertedCount, updated: summary.updatedCount)
        if !summary.potentialDuplicates.isEmpty {
            let count = summary.potentialDuplicates.count
            let names = summary.potentialDuplicates.prefix(5).map { "• \($0)" }.joined(separator: "\n")
            let more = count > 5 ? "\n• and \(count - 5) more" : ""
            message += "\n\n\(count) might already be in your class:\n" + names + more
        }
        if !summary.warnings.isEmpty {
            message += "\n\n" + summary.warnings.joined(separator: "\n")
        }
        return message
    }

    static func countsSentence(inserted: Int, updated: Int) -> String {
        let added = "\(inserted) new \(inserted == 1 ? "student" : "students")"
        switch (inserted > 0, updated > 0) {
        case (true, true): return "Added \(added) and updated \(updated)."
        case (true, false): return "Added \(added)."
        case (false, true): return "Updated \(updated) \(updated == 1 ? "student" : "students")."
        case (false, false): return "Everyone in the file is already in your class, so nothing changed."
        }
    }

}
