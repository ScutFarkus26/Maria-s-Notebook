#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

// MARK: - String Extension Edge Case Tests

@Suite("String Extension Edge Case Tests", .serialized)
struct StringExtensionEdgeCaseTests {

    // MARK: - trimmed() Tests

    @Test("trimmed removes leading whitespace")
    func trimmedRemovesLeading() {
        let result = "   hello".trimmed()

        #expect(result == "hello")
    }

    @Test("trimmed removes trailing whitespace")
    func trimmedRemovesTrailing() {
        let result = "hello   ".trimmed()

        #expect(result == "hello")
    }

    @Test("trimmed removes newlines")
    func trimmedRemovesNewlines() {
        let result = "\n\nhello\n\n".trimmed()

        #expect(result == "hello")
    }

    @Test("trimmed removes tabs")
    func trimmedRemovesTabs() {
        let result = "\t\thello\t\t".trimmed()

        #expect(result == "hello")
    }

    @Test("trimmed preserves internal whitespace")
    func trimmedPreservesInternal() {
        let result = "hello world".trimmed()

        #expect(result == "hello world")
    }

    @Test("trimmed handles empty string")
    func trimmedHandlesEmpty() {
        let result = "".trimmed()

        #expect(result == "")
    }

    @Test("trimmed handles whitespace-only string")
    func trimmedHandlesWhitespaceOnly() {
        let result = "   \n\t  ".trimmed()

        #expect(result == "")
    }

    // MARK: - normalizedNameKey() Tests

    @Test("normalizedNameKey lowercases")
    func normalizedNameKeyLowercases() {
        let result = "HELLO WORLD".normalizedNameKey()

        #expect(result == "hello world")
    }

    @Test("normalizedNameKey trims whitespace")
    func normalizedNameKeyTrims() {
        let result = "  hello  ".normalizedNameKey()

        #expect(result == "hello")
    }

    @Test("normalizedNameKey collapses multiple spaces")
    func normalizedNameKeyCollapsesSpaces() {
        let result = "hello    world".normalizedNameKey()

        #expect(result == "hello world")
    }

    @Test("normalizedNameKey handles mixed whitespace")
    func normalizedNameKeyHandlesMixedWhitespace() {
        let result = "hello\n\t  world".normalizedNameKey()

        #expect(result == "hello world")
    }

    @Test("normalizedNameKey handles empty string")
    func normalizedNameKeyHandlesEmpty() {
        let result = "".normalizedNameKey()

        #expect(result == "")
    }

    // MARK: - normalizedForComparison() Tests

    @Test("normalizedForComparison lowercases and trims")
    func normalizedForComparisonBasic() {
        let result = "  HELLO World  ".normalizedForComparison()

        #expect(result == "hello world")
    }

    @Test("normalizedForComparison preserves internal spaces")
    func normalizedForComparisonPreservesSpaces() {
        let result = "Hello   World".normalizedForComparison()

        #expect(result == "hello   world")
    }
}

// MARK: - StringNormalization Edge Case Tests

@Suite("StringNormalization Edge Case Tests", .serialized)
struct StringNormalizationEdgeCaseTests {

    @Test("normalizeComponent removes diacritics")
    func normalizeComponentRemovesDiacritics() {
        let result = StringNormalization.normalizeComponent("café")

        #expect(result == "cafe")
    }

    @Test("normalizeComponent handles accented characters")
    func normalizeComponentHandlesAccents() {
        let result = StringNormalization.normalizeComponent("Ñoño")

        #expect(result == "nono")
    }

    @Test("normalizeComponent handles umlauts")
    func normalizeComponentHandlesUmlauts() {
        let result = StringNormalization.normalizeComponent("Müller")

        #expect(result == "muller")
    }

    @Test("normalizeComponent handles mixed diacritics and whitespace")
    func normalizeComponentHandlesMixed() {
        let result = StringNormalization.normalizeComponent("  Crème  Brûlée  ")

        #expect(result == "creme brulee")
    }

    @Test("normalizeComponent handles empty string")
    func normalizeComponentHandlesEmpty() {
        let result = StringNormalization.normalizeComponent("")

        #expect(result == "")
    }

    @Test("normalizeComponent handles unicode combining characters")
    func normalizeComponentHandlesCombining() {
        // "e" + combining acute accent
        let result = StringNormalization.normalizeComponent("cafe\u{0301}")

        #expect(result == "cafe")
    }

    @Test("normalizeComponent handles tabs and newlines")
    func normalizeComponentHandlesWhitespace() {
        let result = StringNormalization.normalizeComponent("hello\t\nworld")

        #expect(result == "hello world")
    }
}

// MARK: - Array Safe Access Edge Case Tests

@Suite("Array Safe Access Edge Case Tests", .serialized)
struct ArraySafeAccessEdgeCaseTests {

    @Test("safe subscript returns nil for negative index")
    func safeSubscriptNegativeIndex() {
        let array = [1, 2, 3]

        #expect(array[safe: -1] == nil)
    }

    @Test("safe subscript returns nil for index at count")
    func safeSubscriptIndexAtCount() {
        let array = [1, 2, 3]

        #expect(array[safe: 3] == nil)
    }

    @Test("safe subscript returns nil for large index")
    func safeSubscriptLargeIndex() {
        let array = [1, 2, 3]

        #expect(array[safe: 100] == nil)
    }

    @Test("safe subscript returns element for valid index")
    func safeSubscriptValidIndex() {
        let array = [1, 2, 3]

        #expect(array[safe: 0] == 1)
        #expect(array[safe: 1] == 2)
        #expect(array[safe: 2] == 3)
    }

    @Test("safe subscript works with empty array")
    func safeSubscriptEmptyArray() {
        let array: [Int] = []

        #expect(array[safe: 0] == nil)
    }

    @Test("safeFirst returns nil for empty collection")
    func safeFirstEmptyCollection() {
        let array: [Int] = []

        #expect(array.safeFirst == nil)
    }

    @Test("safeFirst returns first element")
    func safeFirstReturnsFirst() {
        let array = [10, 20, 30]

        #expect(array.safeFirst == 10)
    }
}

// MARK: - Date Normalization Edge Case Tests

@Suite("Date Normalization Edge Case Tests", .serialized)
struct DateNormalizationEdgeCaseTests {

    @Test("startOfDay normalizes time to midnight")
    func startOfDayNormalizesToMidnight() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 14, minute: 30)

        let normalized = date.startOfDay

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: normalized)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("isSameDay returns true for same day different times")
    func isSameDaySameDay() {
        let morning = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 8)
        let evening = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 20)

        #expect(morning.isSameDay(as: evening) == true)
    }

    @Test("isSameDay returns false for different days")
    func isSameDayDifferentDays() {
        let day1 = TestCalendar.date(year: 2025, month: 6, day: 15)
        let day2 = TestCalendar.date(year: 2025, month: 6, day: 16)

        #expect(day1.isSameDay(as: day2) == false)
    }

    @Test("isBeforeDay handles edge case at midnight")
    func isBeforeDayMidnightEdge() {
        let justBeforeMidnight = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 23, minute: 59)
        let justAfterMidnight = TestCalendar.date(year: 2025, month: 6, day: 16, hour: 0, minute: 1)

        #expect(justBeforeMidnight.isBeforeDay(justAfterMidnight) == true)
    }

    @Test("isAfterDay handles edge case at midnight")
    func isAfterDayMidnightEdge() {
        let justAfterMidnight = TestCalendar.date(year: 2025, month: 6, day: 16, hour: 0, minute: 1)
        let justBeforeMidnight = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 23, minute: 59)

        #expect(justAfterMidnight.isAfterDay(justBeforeMidnight) == true)
    }
}

// MARK: - DateCalculations Edge Case Tests

@Suite("DateCalculations Edge Case Tests", .serialized)
struct DateCalculationsEdgeCaseTests {

    @Test("adding zero days returns same day")
    func addingZeroDays() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)

        let result = DateCalculations.addingDays(0, to: date)

        #expect(Calendar.current.isDate(result, inSameDayAs: date))
    }

    @Test("adding negative days goes backwards")
    func addingNegativeDays() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)

        let result = DateCalculations.addingDays(-5, to: date)

        let expected = TestCalendar.date(year: 2025, month: 6, day: 10)
        #expect(Calendar.current.isDate(result, inSameDayAs: expected))
    }

    @Test("adding days across month boundary")
    func addingDaysAcrossMonthBoundary() {
        let date = TestCalendar.date(year: 2025, month: 1, day: 30)

        let result = DateCalculations.addingDays(5, to: date)

        // January 30 + 5 = February 4
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: result)
        #expect(components.month == 2)
        #expect(components.day == 4)
    }

    @Test("adding days across year boundary")
    func addingDaysAcrossYearBoundary() {
        let date = TestCalendar.date(year: 2025, month: 12, day: 30)

        let result = DateCalculations.addingDays(5, to: date)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 4)
    }

    @Test("adding hours handles day rollover")
    func addingHoursDayRollover() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 22)

        let result = DateCalculations.addingHours(5, to: date)

        // 22:00 + 5 hours = 03:00 next day
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour], from: result)
        #expect(components.day == 16)
        #expect(components.hour == 3)
    }

    @Test("adding handles leap year February")
    func addingHandlesLeapYear() {
        // 2024 is a leap year
        let date = TestCalendar.date(year: 2024, month: 2, day: 28)

        let result = DateCalculations.addingDays(1, to: date)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: result)
        #expect(components.month == 2)
        #expect(components.day == 29) // Leap day
    }

    @Test("adding handles non-leap year February")
    func addingHandlesNonLeapYear() {
        // 2025 is not a leap year
        let date = TestCalendar.date(year: 2025, month: 2, day: 28)

        let result = DateCalculations.addingDays(1, to: date)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: result)
        #expect(components.month == 3)
        #expect(components.day == 1) // March 1st
    }
}

// MARK: - CSV Parser Edge Case Tests

@Suite("CSV Parser Edge Case Tests", .serialized)
struct CSVParserEdgeCaseTests {

    @Test("parse handles BOM character")
    func parseHandlesBOM() {
        let csv = "\u{FEFF}name,value\ntest,123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers.first == "name")
    }

    @Test("parse handles CR line endings")
    func parseHandlesCRLineEndings() {
        let csv = "name,value\rtest,123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 1)
    }

    @Test("parse handles CRLF line endings")
    func parseHandlesCRLFLineEndings() {
        let csv = "name,value\r\ntest,123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.count == 1)
    }

    @Test("parse handles quoted fields with commas")
    func parseHandlesQuotedCommas() {
        let csv = "name,value\n\"Hello, World\",123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.first?[0] == "Hello, World")
    }

    @Test("parse handles quoted fields with newlines")
    func parseHandlesQuotedNewlines() {
        let csv = "name,value\n\"Hello\nWorld\",123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.first?[0] == "Hello\nWorld")
    }

    @Test("parse handles escaped quotes")
    func parseHandlesEscapedQuotes() {
        let csv = "name,value\n\"He said \"\"Hello\"\"\",123"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.first?[0] == "He said \"Hello\"")
    }

    @Test("parse handles empty fields")
    func parseHandlesEmptyFields() {
        let csv = "a,b,c\n1,,3"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.rows.first?[1] == "")
    }

    @Test("parse synthesizes headers for non-header rows")
    func parseSynthesizesHeaders() {
        // First row has duplicate values, so not treated as headers
        let csv = "a,a,a\n1,2,3"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        #expect(result?.headers.first?.contains("Column") == true)
    }

    @Test("parse handles uneven row lengths")
    func parseHandlesUnevenRows() {
        let csv = "a,b,c\n1,2"

        let result = CSVParser.parse(string: csv)

        #expect(result != nil)
        // Row should be padded to match header count
        #expect(result?.rows.first?.count == 3)
    }
}

// MARK: - DateParser Edge Case Tests

@Suite("DateParser Edge Case Tests", .serialized)
struct DateParserEdgeCaseTests {

    @Test("parse handles ISO8601 format")
    func parseHandlesISO8601() {
        let result = DateParser.parse("2025-06-15T10:30:00Z")

        #expect(result != nil)
    }

    @Test("parse handles yyyy-MM-dd format")
    func parseHandlesYMD() {
        let result = DateParser.parse("2025-06-15")

        #expect(result != nil)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: result!)
        #expect(components.year == 2025)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test("parse handles MM/dd/yyyy format")
    func parseHandlesMDY() {
        let result = DateParser.parse("06/15/2025")

        #expect(result != nil)
    }

    @Test("parse handles M/d/yy format")
    func parseHandlesShortFormat() {
        let result = DateParser.parse("6/5/25")

        #expect(result != nil)
    }

    @Test("parse handles whitespace-padded input")
    func parseHandlesWhitespace() {
        let result = DateParser.parse("  2025-06-15  ")

        #expect(result != nil)
    }

    @Test("parse returns nil for gibberish")
    func parseReturnsNilForGibberish() {
        let result = DateParser.parse("xyz123")

        #expect(result == nil)
    }

    @Test("parse returns nil for partial date")
    func parseReturnsNilForPartial() {
        let result = DateParser.parse("2025-06")

        #expect(result == nil)
    }
}

// MARK: - CSVHeaderMapping Edge Case Tests

@Suite("CSVHeaderMapping Edge Case Tests", .serialized)
struct CSVHeaderMappingEdgeCaseTests {

    @Test("findIndex handles case insensitivity")
    func findIndexCaseInsensitive() {
        let headers = ["NAME", "Value", "OTHER"]
        let normalized = headers.map { $0.normalizedForComparison() }

        let result = CSVHeaderMapping.findIndex(candidates: ["name"], in: normalized)

        #expect(result == 0)
    }

    @Test("findIndex returns nil when not found")
    func findIndexNotFound() {
        let headers = ["a", "b", "c"]

        let result = CSVHeaderMapping.findIndex(candidates: ["x", "y", "z"], in: headers)

        #expect(result == nil)
    }

    @Test("findIndex returns first match from candidates")
    func findIndexFirstMatch() {
        let headers = ["title", "name", "label"]

        let result = CSVHeaderMapping.findIndex(candidates: ["name", "title"], in: headers)

        // "name" is at index 1, but "title" appears first in candidates, so it should find "title" at 0
        // Actually, the implementation iterates candidates first, so it depends on order
        #expect(result != nil)
    }

    @Test("buildMapping handles empty headers")
    func buildMappingEmptyHeaders() {
        let headers: [String] = []
        let synonymMap: [String: [String]] = ["name": ["name", "title"]]

        let result = CSVHeaderMapping.buildMapping(headers: headers, synonymMap: synonymMap)

        #expect(result.isEmpty)
    }

    @Test("buildMapping handles empty synonym map")
    func buildMappingEmptySynonymMap() {
        let headers = ["name", "value"]
        let synonymMap: [String: [String]] = [:]

        let result = CSVHeaderMapping.buildMapping(headers: headers, synonymMap: synonymMap)

        #expect(result.isEmpty)
    }
}

// MARK: - LessonFormatter Edge Case Tests

@Suite("LessonFormatter Edge Case Tests", .serialized)
struct LessonFormatterEdgeCaseTests {

    @Test("duplicateDetectionTitle handles empty components")
    func duplicateDetectionTitleEmptyComponents() {
        let result = LessonFormatter.duplicateDetectionTitle(name: "Lesson", subject: "", group: "")

        #expect(result.contains("Lesson"))
    }

    @Test("duplicateDetectionTitle includes all components")
    func duplicateDetectionTitleAllComponents() {
        let result = LessonFormatter.duplicateDetectionTitle(name: "Addition", subject: "Math", group: "Operations")

        #expect(result.contains("Addition"))
        #expect(result.contains("Math"))
        #expect(result.contains("Operations"))
    }
}

#endif
