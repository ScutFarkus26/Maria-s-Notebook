#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

/// Snapshot tests for CSV parsing output.
/// These tests verify the parsed structure (headers and rows) is consistent.
@Suite("CSV Parser Snapshots")
struct CSVParserSnapshotTests {

    // MARK: - Helper to format CSV data as text

    private func formatCSVData(_ data: CSVData?) -> String {
        guard let data = data else { return "nil" }

        var output = "Headers: \(data.headers.joined(separator: " | "))\n"
        output += "Row Count: \(data.rows.count)\n"
        output += "---\n"
        for (index, row) in data.rows.enumerated() {
            output += "Row \(index): \(row.joined(separator: " | "))\n"
        }
        return output
    }

    // MARK: - Basic Parsing Tests

    @Test("Parse simple CSV")
    func parse_simpleCSV() {
        let csv = "Name,Age,City\nAlice,30,NYC\nBob,25,LA\nCharlie,35,Chicago"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "simpleCSV")
    }

    @Test("Parse headers only")
    func parse_headersOnly() {
        let csv = "Header1,Header2,Header3"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "headersOnly")
    }

    @Test("Parse single row")
    func parse_singleRow() {
        let csv = "Name,Value\nTest,123"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "singleRow")
    }

    // MARK: - Quoted Field Tests

    @Test("Parse quoted fields")
    func parse_quotedFields() {
        // CSV with quoted fields containing commas
        let csv = "Name,Description,Value\n\"Simple\",\"A simple test\",100\n\"With,Comma\",\"Contains a comma\",200"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "quotedFields")
    }

    @Test("Parse quoted fields with newlines")
    func parse_quotedFieldsWithNewlines() {
        // CSV with quoted field containing a newline
        let csv = "Name,Notes\nAlice,\"Line 1\nLine 2\"\nBob,\"Single line\""

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "quotedFieldsWithNewlines")
    }

    // MARK: - Line Ending Tests

    @Test("Parse windows line endings")
    func parse_windowsLineEndings() {
        let csv = "Name,Value\r\nAlice,1\r\nBob,2\r\nCharlie,3"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "windowsLineEndings")
    }

    @Test("Parse old Mac line endings")
    func parse_oldMacLineEndings() {
        let csv = "Name,Value\rAlice,1\rBob,2\rCharlie,3"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "oldMacLineEndings")
    }

    // MARK: - BOM Handling Tests

    @Test("Parse with UTF8 BOM")
    func parse_withUTF8BOM() {
        let csv = "\u{FEFF}Name,Value\nTest,123"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "withUTF8BOM")
    }

    // MARK: - Synthesized Headers Tests

    @Test("Parse duplicate headers")
    func parse_duplicateHeaders() {
        let csv = "Name,Name,Value\nAlice,Smith,100\nBob,Jones,200"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "duplicateHeaders")
    }

    @Test("Parse empty header field")
    func parse_emptyHeaderField() {
        let csv = "Name,,Value\nAlice,Extra,100"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "emptyHeaderField")
    }

    @Test("Parse numeric headers")
    func parse_numericHeaders() {
        let csv = "1,2,3\nA,B,C\nD,E,F"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "numericHeaders")
    }

    // MARK: - Edge Cases

    @Test("Parse empty fields")
    func parse_emptyFields() {
        let csv = "A,B,C\n1,,3\n,2,\n,,"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "emptyFields")
    }

    @Test("Parse unequal row lengths")
    func parse_unequalRowLengths() {
        let csv = "A,B,C,D\n1,2\n1,2,3\n1,2,3,4,5"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "unequalRowLengths")
    }

    @Test("Parse whitespace in fields")
    func parse_whitespaceInFields() {
        let csv = "Name,Value\n  Alice  ,  100\nBob,200"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "whitespaceInFields")
    }

    @Test("Parse special characters")
    func parse_specialCharacters() {
        // Use actual Unicode characters instead of escape sequences
        let csv = "Name,Symbol\nEuro,€\nYen,¥\nEmoji,🎉"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "specialCharacters")
    }

    // MARK: - Real-World Example

    @Test("Parse student import format")
    func parse_studentImportFormat() {
        let csv = "First Name,Last Name,Birthday,Level\nEmma,Johnson,2015-06-15,lower\nLiam,Smith,2016-03-22,lower\nOlivia,Williams,2014-09-08,upper\nNoah,Brown,2015-01-30,upper\nAva,Davis,2016-11-05,lower"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "studentImportFormat")
    }

    @Test("Parse lesson import format")
    func parse_lessonImportFormat() {
        let csv = "Name,Subject,Group,Subheading\nAddition Facts,Math,Operations,Basic addition practice\nSubtraction Facts,Math,Operations,Basic subtraction practice\nReading Fluency,Language,Reading,Oral reading practice"

        let result = CSVParser.parse(string: csv)
        #expect(result != nil)
        assertTextSnapshot(formatCSVData(result), named: "lessonImportFormat")
    }

    // MARK: - Date Parsing Tests

    @Test("Date parse common formats")
    func dateParse_commonFormats() {
        let dateStrings = [
            "2025-01-15",
            "01/15/2025",
            "Jan 15, 2025",
        ]

        var output = "Date Parsing Results:\n"
        for dateStr in dateStrings {
            let result = DateParser.parse(dateStr)
            let formatted = result.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
            output += "\(dateStr) -> \(formatted)\n"
        }

        assertTextSnapshot(output, named: "commonFormats")
    }

    @Test("Date parse invalid dates")
    func dateParse_invalidDates() {
        let dateStrings = [
            "",
            "invalid",
            "not a date",
        ]

        var output = "Invalid Date Parsing Results:\n"
        for dateStr in dateStrings {
            let result = DateParser.parse(dateStr)
            output += "\"\(dateStr)\" -> \(result == nil ? "nil" : "parsed")\n"
        }

        assertTextSnapshot(output, named: "invalidDates")
    }
}

#endif
