import Foundation
import Testing
@testable import CosmicDaybook

/// What the "Students Imported" alert and the import failure alert say.
@Suite("Student import messages")
@MainActor
struct ImportCommitMessageTests {

    private func summary(
        inserted: Int, updated: Int, duplicates: [String] = [], warnings: [String] = []
    ) -> StudentCSVImporter.Summary {
        StudentCSVImporter.Summary(
            totalRows: inserted + updated, insertedCount: inserted, updatedCount: updated,
            potentialDuplicates: duplicates, warnings: warnings
        )
    }

    @Test("The counts read as a sentence, with real plurals")
    func countsSentence() {
        #expect(ImportCommitService.countsSentence(inserted: 3, updated: 2) == "Added 3 new students and updated 2.")
        #expect(ImportCommitService.countsSentence(inserted: 1, updated: 0) == "Added 1 new student.")
        #expect(ImportCommitService.countsSentence(inserted: 0, updated: 1) == "Updated 1 student.")
        #expect(ImportCommitService.countsSentence(inserted: 0, updated: 4) == "Updated 4 students.")
        #expect(ImportCommitService.countsSentence(inserted: 0, updated: 0)
            == "Everyone in the file is already in your class, so nothing changed.")
    }

    @Test("Possible duplicates are listed by name, five at most")
    func duplicatesListed() {
        let names = ["Ava Stone", "Ben Cho", "Cy Marks", "Dina Ross", "Eli Park", "Fay Lin", "Gil Ott"]
        let message = ImportCommitService.message(for: summary(inserted: 2, updated: 0, duplicates: names))
        #expect(message.hasPrefix("Added 2 new students."))
        #expect(message.contains("7 might already be in your class:\n• Ava Stone"))
        #expect(message.contains("• Eli Park"))
        #expect(!message.contains("Fay Lin"))
        #expect(message.hasSuffix("• and 2 more"))
        #expect(!message.contains("Potential duplicates"))
    }

    @Test("Skipped lines follow the counts without a developer heading")
    func skippedLines() {
        let line = "Line 4 skipped: it's missing a first or last name."
        let message = ImportCommitService.message(for: summary(inserted: 1, updated: 0, warnings: [line]))
        #expect(message == "Added 1 new student.\n\n" + line)
    }

    @Test("A file that can't be read gets the importer's plain sentence or the shared file wording")
    func failureAlert() {
        let alert = StudentsCSVImportHandler.failureAlert(for: StudentCSVImporter.ImportError.unreadableText)
        #expect(alert.title == "Couldn't Import Students")
        #expect(alert.message.hasPrefix("This file's text can't be read."))

        let raw = NSError(
            domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
            userInfo: [NSFilePathErrorKey: "/Users/danny/Desktop/class.csv"]
        )
        let foreign = StudentsCSVImportHandler.failureAlert(for: raw)
        #expect(foreign.message == "Cosmic Daybook can't open this spreadsheet. Choose it again.")
        #expect(!foreign.message.contains("/Users"))
    }
}
