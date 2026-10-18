import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #43: a spreadsheet with a blank first line lost its
/// header row (the blank line was taken for the "header" and failed the
/// test), so the import asked for a mapping or took the real header for a
/// child named "First Name Last Name". Blank records now go before the
/// header is looked for and from the rows, and warnings still name the
/// spreadsheet's own line.
@Suite("Student CSV import blank lines (fix 10-17 St)")
@MainActor
struct StudentCSVImportFix1017StTests {

    private func parse(_ csv: String) throws -> StudentCSVImporter.Parsed {
        try StudentCSVImporter.parse(
            data: Data(csv.utf8), mapping: nil, existingFullKeys: [], existingNameKeys: []
        )
    }

    @Test("A blank first line doesn't hide the header row")
    func blankFirstLine() throws {
        let parsed = try parse("\nFirst Name,Last Name,Birthday\nMaya,Smith,3/5/15\n")
        #expect(parsed.rows.map { "\($0.firstName) \($0.lastName)" } == ["Maya Smith"])
        #expect(parsed.warnings.isEmpty)
    }

    @Test("Empty spreadsheet rows (commas only) are skipped, and warnings name the right line")
    func emptyRowsAreSkipped() throws {
        let csv = ",,\nFirst Name,Last Name,Birthday\n,,\nMaya,Smith,soon\n , ,\nLeo,Brown,\n"
        let parsed = try parse(csv)
        #expect(parsed.rows.map(\.firstName) == ["Maya", "Leo"])
        #expect(!parsed.warnings.contains { $0.contains("missing a first or last name") })
        #expect(parsed.warnings.contains { $0.hasPrefix("Line 4:") && $0.contains("couldn\u{2019}t read") })
        #expect(parsed.warnings.count == 1)
    }

    @Test("A file with no header row loses only its blank lines")
    func headerlessFileKeepsEveryChild() throws {
        let table = try #require(StudentCSVImporter.readTable(Data("Maya,Smith,\n,,\n\nLeo,Brown,\n".utf8)))
        #expect(table.rows == [["Maya", "Smith", ""], ["Leo", "Brown", ""]])
    }
}
