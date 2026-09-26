import Foundation
@testable import CosmicDaybook

// `CSVParser` as it stood before it read UTF-8 bytes (2026-09-26), copied
// verbatim — only the type is renamed and `public` dropped. `CSVByteScannerTests`
// compares the new parser against it, so do not "fix" or modernise this code:
// its only job is to be the old code.

enum LegacyCSVParser {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func parse(string: String) -> CSVData? {
        // Remove BOM if present
        var content = string
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }
        
        // Normalize line endings to \n
        content = content.replacingOccurrences(of: "\r\n", with: "\n")
        content = content.replacingOccurrences(of: "\r", with: "\n")
        
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
    
    static func parse(data: Data) -> CSVData? {
        // Try UTF8
        if let string = String(data: data, encoding: .utf8) {
            return parse(string: string)
        }
        // Fallback to ISO Latin 1
        if let string = String(data: data, encoding: .isoLatin1) {
            return parse(string: string)
        }
        return nil
    }
}
