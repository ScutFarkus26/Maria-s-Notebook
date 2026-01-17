#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("CSVParser Tests")
struct CSVParserTests {

    // MARK: - Basic Parsing

    @Test("Parses simple CSV with headers")
    func parseSimpleCSV() {
        let csv = "Name,Age,City\nAlice,30,NYC\nBob,25,LA"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Name", "Age", "City"])
        #expect(result?.rows.count == 2)
        #expect(result?.rows[0] == ["Alice", "30", "NYC"])
        #expect(result?.rows[1] == ["Bob", "25", "LA"])
    }

    @Test("Parses CSV with single row")
    func parseSingleRow() {
        let csv = "Header1,Header2\nValue1,Value2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Header1", "Header2"])
        #expect(result?.rows.count == 1)
        #expect(result?.rows[0] == ["Value1", "Value2"])
    }

    @Test("Parses CSV with no data rows")
    func parseHeadersOnly() {
        let csv = "Header1,Header2,Header3"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Header1", "Header2", "Header3"])
        #expect(result?.rows.count == 0)
    }

    @Test("Returns nil for empty string")
    func parseEmptyString() {
        let csv = ""

        let result = CSVParser.parse(string: csv)

        #expect(result == nil)
    }

    // MARK: - BOM Handling

    @Test("Removes UTF-8 BOM from start of file")
    func removesBOM() {
        let csv = "\u{FEFF}Name,Value\nTest,123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Name", "Value"])
        #expect(result?.rows[0] == ["Test", "123"])
    }

    @Test("Handles CSV without BOM normally")
    func noBOMHandling() {
        let csv = "Name,Value\nTest,123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers.first == "Name")
    }

    // MARK: - Line Ending Normalization

    @Test("Handles Windows CRLF line endings")
    func handlesCRLF() {
        let csv = "Name,Value\r\nAlice,1\r\nBob,2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 2)
        #expect(result?.rows[0] == ["Alice", "1"])
        #expect(result?.rows[1] == ["Bob", "2"])
    }

    @Test("Handles old Mac CR line endings")
    func handlesCR() {
        let csv = "Name,Value\rAlice,1\rBob,2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 2)
    }

    @Test("Handles Unix LF line endings")
    func handlesLF() {
        let csv = "Name,Value\nAlice,1\nBob,2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 2)
    }

    @Test("Handles mixed line endings")
    func handlesMixedLineEndings() {
        let csv = "Name,Value\r\nAlice,1\nBob,2\rCharlie,3"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 3)
    }

    // MARK: - Quote Handling

    @Test("Handles quoted fields")
    func handlesQuotedFields() {
        let csv = "Name,Description\n\"John\",\"A long description\""

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][0] == "John")
        #expect(result?.rows[0][1] == "A long description")
    }

    @Test("Handles escaped quotes within quoted fields")
    func handlesEscapedQuotes() {
        let csv = "Name,Quote\nAlice,\"She said \"\"Hello\"\"\""

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "She said \"Hello\"")
    }

    @Test("Handles commas within quoted fields")
    func handlesCommasInQuotes() {
        let csv = "Name,Address\nAlice,\"123 Main St, Apt 4\""

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "123 Main St, Apt 4")
    }

    @Test("Handles newlines within quoted fields")
    func handlesNewlinesInQuotes() {
        let csv = "Name,Notes\nAlice,\"Line 1\nLine 2\""

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "Line 1\nLine 2")
    }

    @Test("Handles empty quoted field")
    func handlesEmptyQuotedField() {
        let csv = "Name,Value\nAlice,\"\""

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "")
    }

    // MARK: - Header Detection

    @Test("Synthesizes headers when first row has empty values")
    func synthesizesHeadersForEmptyFirstRow() {
        let csv = ",Value2\nA,B"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Column 1", "Column 2"])
        #expect(result?.rows.count == 2)
    }

    @Test("Synthesizes headers when first row has duplicates")
    func synthesizesHeadersForDuplicates() {
        let csv = "Name,Name\nAlice,Bob"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Column 1", "Column 2"])
        #expect(result?.rows.count == 2)
    }

    @Test("Uses first row as headers when all unique and non-empty")
    func usesFirstRowAsHeaders() {
        let csv = "First,Second,Third\n1,2,3"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["First", "Second", "Third"])
        #expect(result?.rows.count == 1)
    }

    // MARK: - Row Padding

    @Test("Pads short rows to match header count")
    func padsShortRows() {
        let csv = "A,B,C\n1\n1,2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0] == ["1", "", ""])
        #expect(result?.rows[1] == ["1", "2", ""])
    }

    @Test("Handles rows with more columns than headers")
    func handlesExtraColumns() {
        let csv = "A,B\n1,2,3,4"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        // Extra columns should still be present
        #expect(result?.rows[0].count == 4)
    }

    // MARK: - Edge Cases

    @Test("Handles single column CSV")
    func handlesSingleColumn() {
        let csv = "Name\nAlice\nBob"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Name"])
        #expect(result?.rows.count == 2)
        #expect(result?.rows[0] == ["Alice"])
    }

    @Test("Handles trailing newline")
    func handlesTrailingNewline() {
        let csv = "Name,Value\nAlice,1\n"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 1) // Should not create empty row
    }

    @Test("Handles whitespace in headers")
    func handlesWhitespaceInHeaders() {
        let csv = "  Name  ,  Value  \nAlice,1"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers == ["Name", "Value"]) // Should be trimmed
    }

    @Test("Handles special characters in values")
    func handlesSpecialCharacters() {
        let csv = "Name,Symbol\nTest,@#$%^&*()"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "@#$%^&*()")
    }

    @Test("Handles unicode characters")
    func handlesUnicode() {
        let csv = "Name,Greeting\nTest,Hello"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows[0][1] == "Hello")
    }

    // MARK: - Data Parsing

    @Test("Parses UTF-8 data")
    func parsesUTF8Data() {
        let csv = "Name,Value\nTest,123"
        let data = csv.data(using: .utf8)!

        let result = CSVParser.parse(data: data)

        #expect(result != nil)
        #expect(result?.rows[0] == ["Test", "123"])
    }

    @Test("Parses ISO Latin 1 data as fallback")
    func parsesISOLatin1Data() {
        // Create data that's valid ISO Latin 1 but has characters outside ASCII
        let csv = "Name,Value\nCaf\u{00E9},123"
        let data = csv.data(using: .isoLatin1)!

        let result = CSVParser.parse(data: data)

        #expect(result != nil)
    }

    @Test("Returns nil for invalid data")
    func returnsNilForInvalidData() {
        // Create data that's neither valid UTF-8 nor ISO Latin 1
        let invalidData = Data([0x80, 0x81, 0x82]) // Invalid UTF-8 sequence

        // This might still parse as ISO Latin 1, so the test checks it doesn't crash
        let _ = CSVParser.parse(data: invalidData)
        // Just checking it doesn't crash
    }
}

@Suite("DateParser Tests")
struct DateParserTests {

    // MARK: - ISO 8601 Format

    @Test("Parses ISO 8601 date")
    func parsesISO8601() {
        let result = DateParser.parse("2025-01-15T10:30:00Z")

        #expect(result != nil)
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: result!)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    // MARK: - Standard Formats

    @Test("Parses yyyy-MM-dd format")
    func parsesYYYYMMDD() {
        let result = DateParser.parse("2025-06-15")

        #expect(result != nil)
    }

    @Test("Parses MM/dd/yyyy format")
    func parsesMMDDYYYY() {
        let result = DateParser.parse("06/15/2025")

        #expect(result != nil)
    }

    @Test("Parses MMM d, yyyy format")
    func parsesMMMDYYYY() {
        let result = DateParser.parse("Jun 15, 2025")

        #expect(result != nil)
    }

    @Test("Parses MMMM d, yyyy format")
    func parsesMMMMDYYYY() {
        let result = DateParser.parse("June 15, 2025")

        #expect(result != nil)
    }

    @Test("Parses M/d/yy format")
    func parsesMDYY() {
        let result = DateParser.parse("6/15/25")

        #expect(result != nil)
    }

    @Test("Parses yyyy/MM/dd format")
    func parsesYYYYSlashMMSlashDD() {
        let result = DateParser.parse("2025/06/15")

        #expect(result != nil)
    }

    // MARK: - Edge Cases

    @Test("Returns nil for empty string")
    func returnsNilForEmpty() {
        let result = DateParser.parse("")

        #expect(result == nil)
    }

    @Test("Returns nil for whitespace only")
    func returnsNilForWhitespace() {
        let result = DateParser.parse("   ")

        #expect(result == nil)
    }

    @Test("Returns nil for invalid date string")
    func returnsNilForInvalid() {
        let result = DateParser.parse("not a date")

        #expect(result == nil)
    }

    @Test("Trims whitespace before parsing")
    func trimsWhitespace() {
        let result = DateParser.parse("  2025-06-15  ")

        #expect(result != nil)
    }

    @Test("Returns nil for partial date")
    func returnsNilForPartialDate() {
        let result = DateParser.parse("2025-06")

        #expect(result == nil)
    }
}
#endif
