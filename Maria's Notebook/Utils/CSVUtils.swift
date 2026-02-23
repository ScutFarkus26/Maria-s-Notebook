import Foundation

public struct CSVData: Identifiable {
    public let id = UUID()
    public let headers: [String]
    public let rows: [[String]]
}

public enum CSVParser {
    public static func parse(string: String) -> CSVData? {
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
        let chars = Array(content)
        var i = 0
        
        func appendField() {
            currentRow.append(currentField)
            currentField = ""
        }
        
        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
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
                    insideQuotes = true
                case ",":
                    appendField()
                case "\n":
                    appendField()
                    rows.append(currentRow)
                    currentRow = []
                default:
                    currentField.append(c)
                }
            }
            i += 1
        }
        // Append last field and row if any
        appendField()
        if !currentRow.isEmpty {
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
            let maxColumns = rows.map { $0.count }.max() ?? 0
            let headers = (1...maxColumns).map { "Column \($0)" }
            return CSVData(headers: headers, rows: rows.map { row in
                row + Array(repeating: "", count: max(0, maxColumns - row.count))
            })
        }
    }
    
    public static func parse(data: Data) -> CSVData? {
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

public enum DateParser {
    static let formats = [
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "dd/MM/yyyy",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "M/d/yy",
        "d/M/yy",
        "yyyy/MM/dd",
        "yyyy-MM-dd'T'HH:mm:ssZ"
    ]
    
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static let cachedFormatters: [String: DateFormatter] = {
        var dict: [String: DateFormatter] = [:]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = fmt
            dict[fmt] = df
        }
        return dict
    }()

    public static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmed()
        if trimmed.isEmpty { return nil }

        if let date = iso.date(from: trimmed) {
            return date
        }
        for fmt in formats {
            if let df = cachedFormatters[fmt], let date = df.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

