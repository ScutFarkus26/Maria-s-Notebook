import Foundation

public struct CSVData: Identifiable {
    public let id = UUID()
    public let headers: [String]
    public let rows: [[String]]
}

public enum CSVParser {
    public static func parse(string: String) -> CSVData? {
        let content = normalized(string)
        // Bytes when that reads the same as characters (nearly always);
        // characters, as before, when it might not.
        let rows = CSVRecordScanner.records(in: content) ?? characterRecords(in: content)
        return table(from: rows)
    }

    /// The text the records are read from: a leading BOM removed and line
    /// endings normalized to "\n". Text without a carriage return is left as
    /// it is — the replacements would find nothing to replace.
    static func normalized(_ string: String) -> String {
        // Remove BOM if present
        var content = string
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }

        // Normalize line endings to \n
        if content.utf8.contains(0x0D) {
            content = content.replacingOccurrences(of: "\r\n", with: "\n")
            content = content.replacingOccurrences(of: "\r", with: "\n")
        }
        return content
    }

    /// The records of normalized `content`, read one `Character` at a time.
    /// The reference reading: `CSVRecordScanner` reads UTF-8 bytes and hands
    /// back here whenever its reading could differ from this one.
    static func characterRecords(in content: String) -> [[String]] {
        // Parse CSV rows and fields
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        // True once any field content (a char, comma, or opening quote) has been seen since
        // the last record-terminating newline. Lets us distinguish a genuine final record
        // (even an empty quoted one like `""` at EOF) from the empty state left after a
        // trailing "\n" — so we never synthesize a spurious blank row, nor drop a real one.
        var pendingRecord = false
        let chars = Array(content)
        var i = 0

        func appendField() {
            currentRow.append(currentField)
            currentField = ""
        }

        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                pendingRecord = true
                if c == "\"" {
                    // Check if next char is also quote (escaped quote)
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                switch c {
                case "\"":
                    pendingRecord = true
                    insideQuotes = true
                case ",":
                    pendingRecord = true
                    appendField()
                case "\n":
                    appendField()
                    rows.append(currentRow)
                    currentRow = []
                    pendingRecord = false
                default:
                    pendingRecord = true
                    currentField.append(c)
                }
            }
            i += 1
        }
        // Flush a trailing record only when one is genuinely in progress (content seen
        // since the last newline). A file ending in "\n" leaves pendingRecord false, so no
        // blank row is synthesized; a final record without a trailing newline — including a
        // lone empty quoted field — is correctly flushed.
        if pendingRecord {
            appendField()
            rows.append(currentRow)
        }
        return rows
    }

    /// Headers and padded rows from the parsed records: the first record is
    /// the header row when its trimmed fields are non-empty and unique;
    /// otherwise headers are synthesized ("Column 1", …).
    static func table(from rows: [[String]]) -> CSVData? {
        // If empty result, return nil
        if rows.isEmpty { return nil }

        // Check if first row can be header
        let firstRow = rows[0]

        // Trim fields in first row
        let trimmedHeaders = firstRow.map { $0.trimmed() }

        let allNonEmpty = !trimmedHeaders.contains(where: { $0.isEmpty })
        let uniqueHeaders = Set(trimmedHeaders).count == trimmedHeaders.count

        if allNonEmpty && uniqueHeaders {
            // Use first row as headers, rest as data
            let dataRows = Array(rows.dropFirst())
            return CSVData(headers: trimmedHeaders, rows: dataRows.map { row in
                row + Array(repeating: "", count: max(0, trimmedHeaders.count - row.count))
            })
        } else {
            // Synthesize headers
            let maxColumns = rows.map(\.count).max() ?? 0
            let headers = (1...maxColumns).map { "Column \($0)" }
            return CSVData(headers: headers, rows: rows.map { row in
                row + Array(repeating: "", count: max(0, maxColumns - row.count))
            })
        }
    }

    public static func parse(data: Data) -> CSVData? {
        text(of: data).flatMap { parse(string: $0) }
    }

    /// Like `parse(data:)`, except that the first record is the header row
    /// whenever `isHeaderRow` recognizes it, even with a blank or repeated
    /// cell. `table(from:)` reads either as "this file has no header", which
    /// turned a real header row into a row of data (a student named "First
    /// Name Last Name"). Blank cells are named "Column N" and a repeated name
    /// gets " 2", " 3", so every column can still be picked.
    static func parse(data: Data, headerRow isHeaderRow: ([String]) -> Bool) -> CSVData? {
        guard let string = text(of: data) else { return nil }
        let content = normalized(string)
        let rows = CSVRecordScanner.records(in: content) ?? characterRecords(in: content)
        guard let first = rows.first, isHeaderRow(first) else { return table(from: rows) }
        let headers = uniqueHeaders(first)
        return CSVData(headers: headers, rows: rows.dropFirst().map { row in
            row + Array(repeating: "", count: max(0, headers.count - row.count))
        })
    }

    /// The header cells trimmed, blanks named by position, repeats numbered.
    static func uniqueHeaders(_ cells: [String]) -> [String] {
        var seen = Set<String>()
        return cells.enumerated().map { index, cell in
            let trimmed = cell.trimmed()
            let base = trimmed.isEmpty ? "Column \(index + 1)" : trimmed
            var name = base
            var copy = 2
            while !seen.insert(name).inserted {
                name = "\(base) \(copy)"
                copy += 1
            }
            return name
        }
    }

    /// The file's text: UTF-8, else ISO Latin 1.
    private static func text(of data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// Dates in a spreadsheet: birthdays and start dates.
///
/// Each shape is read strictly, by its parts. `DateFormatter` read "3/5/15"
/// with its `yyyy-MM-dd` pattern as the year 3, and those birthdays synced to
/// every device. Here a year written with two digits is always a two-digit
/// year, the parts must name a real day, and a year before 1900 is refused
/// rather than stored.
public enum DateParser {
    /// What one cell held.
    enum Outcome: Equatable {
        /// Nothing in the cell.
        case empty
        case date(Date)
        /// A real day, but before `earliestYear`: almost certainly a typo or
        /// a two-digit year read the old way.
        case tooEarly(year: Int)
        /// Not a date in any shape the importer reads.
        case unreadable
    }

    /// The earliest year a date is taken in.
    static let earliestYear = 1900

    /// Two-digit years below this are 20xx, the rest 19xx — the split
    /// `DateFormatter` makes by default (`twoDigitStartDate`, 1950).
    static let twoDigitPivot = 50

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = DateFormatters.iso8601DateTime

    /// The one shape with a time and zone, read as an absolute instant.
    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        df.isLenient = false
        return df
    }()

    /// Month names ("Mar 5, 2015", "March 5, 2015"), English, as before.
    private static let monthNameFormatters: [DateFormatter] = ["MMM d, yyyy", "MMMM d, yyyy"].map { format in
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = format
        df.isLenient = false
        return df
    }

    private static let gmtCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal
    }()

    public static func parse(_ value: String) -> Date? {
        if case .date(let date) = outcome(value) { return date }
        return nil
    }

    /// Reads one cell. Date-only shapes land at local midnight of the day
    /// they name; the date-time shape keeps its instant.
    static func outcome(_ value: String) -> Outcome {
        let trimmed = value.trimmed()
        if trimmed.isEmpty { return .empty }

        if trimmed.contains("T") {
            guard let instant = iso.date(from: trimmed) ?? dateTimeFormatter.date(from: trimmed) else {
                return .unreadable
            }
            let year = AppCalendar.shared.component(.year, from: instant)
            return year < earliestYear ? .tooEarly(year: year) : .date(instant)
        }
        if let numeric = numericDay(trimmed) {
            return localDay(numeric)
        }
        if trimmed.range(of: #"^[A-Za-z]{3,9} \d{1,2}, \d{4}$"#, options: .regularExpression) != nil {
            for formatter in monthNameFormatters {
                if let gmtMidnight = formatter.date(from: trimmed) {
                    return localDay(gmtCalendar.dateComponents([.year, .month, .day], from: gmtMidnight))
                }
            }
        }
        return .unreadable
    }

    /// Year, month and day from an all-number date: `yyyy-MM-dd` or
    /// `yyyy/MM/dd`, or month and day then a two- or four-digit year
    /// (`M/d/yy`, `MM/dd/yyyy`), read month first and day first only when
    /// the first number can't be a month. Nil when the text isn't one of
    /// these shapes or names no real day.
    static func numericDay(_ text: String) -> DateComponents? {
        let separators = text.filter { $0 == "-" || $0 == "/" }
        guard separators.count == 2, Set(separators).count == 1, let separator = separators.first else {
            return nil
        }
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy { ("0"..."9").contains($0) }
        }) else { return nil }
        let numbers = parts.compactMap { Int($0) }

        let candidates: [DateComponents]
        if parts[0].count == 4 {
            guard (1...2).contains(parts[1].count), (1...2).contains(parts[2].count) else { return nil }
            candidates = [DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])]
        } else {
            guard (1...2).contains(parts[0].count), (1...2).contains(parts[1].count) else { return nil }
            let year: Int
            switch parts[2].count {
            case 2: year = numbers[2] < twoDigitPivot ? 2000 + numbers[2] : 1900 + numbers[2]
            case 4: year = numbers[2]
            default: return nil
            }
            candidates = [
                DateComponents(year: year, month: numbers[0], day: numbers[1]),
                DateComponents(year: year, month: numbers[1], day: numbers[0])
            ]
        }
        return candidates.first(where: isRealDay)
    }

    private static func isRealDay(_ ymd: DateComponents) -> Bool {
        guard let year = ymd.year, let month = ymd.month, let day = ymd.day,
              year >= 1, (1...12).contains(month), day >= 1,
              let first = gmtCalendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = gmtCalendar.range(of: .day, in: .month, for: first) else { return false }
        return days.contains(day)
    }

    /// Local midnight of the day `comps` names (the importer keys and
    /// compares children by local day), or why it was refused.
    private static func localDay(_ comps: DateComponents) -> Outcome {
        guard let year = comps.year else { return .unreadable }
        if year < earliestYear { return .tooEarly(year: year) }
        let day = DateComponents(year: year, month: comps.month, day: comps.day)
        guard let date = AppCalendar.shared.date(from: day) else { return .unreadable }
        return .date(date)
    }
}
