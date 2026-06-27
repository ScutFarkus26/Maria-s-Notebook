import Foundation
import Testing
@testable import Maria_s_Notebook

// Regression coverage for CSVParser.parse — added after a trailing-newline bug that
// synthesized a spurious blank data row on every import. These lock in RFC-4180-ish
// behavior around record termination, quoting, and end-of-file edge cases.
//
// Each input begins with a real unique header row (the shape the app always feeds the
// parser), so the parser uses it as headers and returns the remaining records as
// `rows`. Column counts are kept consistent with the header so width-padding never
// surprises the assertions.
@Suite("CSV parser")
struct CSVParserTests {

    @Test("A trailing newline does not produce a spurious blank row")
    func trailingNewlineNoBlankRow() {
        // The original bug: a trailing "\n" yielded an extra empty data row.
        let parsed = CSVParser.parse(string: "a,b\n1,2\n3,4\n")
        #expect(parsed?.rows == [["1", "2"], ["3", "4"]])
    }

    @Test("A file without a trailing newline keeps its last row")
    func noTrailingNewlineKeepsLastRow() {
        let parsed = CSVParser.parse(string: "a,b\n1,2\n3,4")
        #expect(parsed?.rows == [["1", "2"], ["3", "4"]])
    }

    @Test("Quoted fields preserve embedded newlines and commas")
    func quotedFieldsPreserveEmbeddedDelimiters() {
        let parsed = CSVParser.parse(string: "a,b\n1,\"hi\nthere\"\n2,\"x,y\"\n")
        #expect(parsed?.rows == [["1", "hi\nthere"], ["2", "x,y"]])
    }

    @Test("Trailing empty field is preserved")
    func trailingEmptyFieldPreserved() {
        let parsed = CSVParser.parse(string: "a,b\n1,\n2,\n")
        #expect(parsed?.rows == [["1", ""], ["2", ""]])
    }

    @Test("A lone empty quoted field at end of file is a real (empty) record")
    func loneEmptyQuotedFieldAtEOF() {
        // After the closing quote both field and row are empty, but a record IS in
        // progress, so it must NOT be dropped. Single-column input avoids width padding.
        let parsed = CSVParser.parse(string: "label\nAda\n\"\"")
        #expect(parsed?.rows == [["Ada"], [""]])
    }

    @Test("CRLF line endings are normalized")
    func crlfNormalized() {
        let parsed = CSVParser.parse(string: "a,b\r\n1,2\r\n3,4\r\n")
        #expect(parsed?.rows == [["1", "2"], ["3", "4"]])
    }

    @Test("Escaped doubled quotes decode to a single quote")
    func escapedQuotes() {
        let parsed = CSVParser.parse(string: "a\n\"she said \"\"hi\"\"\"\n")
        #expect(parsed?.rows == [["she said \"hi\""]])
    }
}
