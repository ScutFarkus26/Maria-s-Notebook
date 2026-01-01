import Foundation
import SwiftData

// A CSV importer for Lesson records that supports parse-first and commit-later workflows.
enum LessonCSVImporter {
    // MARK: - Row DTO
    struct Row {
        var name: String
        var subject: String
        var group: String
        var subheading: String
        var writeUp: String
    }

    // MARK: - Parsed (dry run)
    struct Parsed {
        let rows: [Row]
        let totalRows: Int
        let potentialDuplicates: [String]
        let warnings: [String]
    }

    // MARK: - Summary (post-commit)
    struct Summary {
        let totalRows: Int
        let insertedCount: Int
        let potentialDuplicates: [String]
        let warnings: [String]
    }

    // MARK: - Errors
    enum ImportError: Error, LocalizedError {
        case empty
        case missingHeader(String)
        case malformedRow(Int)
        case encoding(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The file appears to be empty."
            case .missingHeader(let h):
                return "Missing required column: \(h)"
            case .malformedRow(let n):
                return "Malformed row at line \(n)."
            case .encoding(let msg):
                return msg
            }
        }
    }

    // MARK: - Public API
    /// Convenience one-shot import: parse then commit.
    static func importLessons(from data: Data, existingLessons: [Lesson], into context: ModelContext) throws -> Summary {
        let parsed = try parse(data: data, existingLessons: existingLessons)
        let inserted = try commit(parsed: parsed, into: context)
        return Summary(totalRows: parsed.totalRows, insertedCount: inserted, potentialDuplicates: parsed.potentialDuplicates, warnings: parsed.warnings)
    }

    /// Parse CSV into rows and detect potential duplicates against existing lessons.
    static func parse(data: Data, existingLessons: [Lesson]) throws -> Parsed {
        // Decode text as UTF-8, fallback UTF-16
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError.encoding("Unsupported text encoding; please use UTF-8.")
        }
        // Strip BOM if present
        if text.first == "\u{feff}" { text.removeFirst() }

        let records = try splitCSVIntoRecords(text)
        guard let header = records.first else { throw ImportError.empty }

        // Synonyms for flexible headers
        let synonyms: [String: [String]] = [
            "name": ["name", "lesson", "title"],
            "subject": ["subject"],
            "group": ["group", "category"],
            "subheading": ["subheading", "subtitle"],
            "writeup": ["writeup", "write up", "notes", "description"]
        ]

        let headerMap = try mapHeaders(header, synonyms: synonyms)

        // Build existing keys for duplicate detection
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let existingKeys: Set<String> = Set(existingLessons.map { l in
            [norm(l.name), norm(l.subject), norm(l.group)].joined(separator: "|")
        })

        var rows: [Row] = []
        var potentialDupTitles: [String] = []
        var warnings: [String] = []

        for (i, record) in records.dropFirst().enumerated() {
            // Tolerate blank lines
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }

            func value(_ key: String) -> String {
                if let idx = headerMap[key], idx < record.count { return record[idx] } else { return "" }
            }

            let name = value("name").trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = value("subject").trimmingCharacters(in: .whitespacesAndNewlines)
            let group = value("group").trimmingCharacters(in: .whitespacesAndNewlines)
            let subheading = value("subheading").trimmingCharacters(in: .whitespacesAndNewlines)
            let writeUp = value("writeup").trimmingCharacters(in: .whitespacesAndNewlines)

            if name.isEmpty || subject.isEmpty {
                warnings.append("Row \(i + 2): Missing required Name or Subject; row skipped.")
                continue
            }

            let row = Row(name: name, subject: subject, group: group, subheading: subheading, writeUp: writeUp)
            rows.append(row)

            let key = [norm(name), norm(subject), norm(group)].joined(separator: "|")
            if existingKeys.contains(key) {
                let title = group.isEmpty ? "\(name) — \(subject)" : "\(name) — \(subject) • \(group)"
                potentialDupTitles.append(title)
            }
        }

        return Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: potentialDupTitles, warnings: warnings)
    }

    /// Commit parsed rows by inserting new Lesson objects; always inserts (does not skip duplicates).
    static func commit(parsed: Parsed, into context: ModelContext) throws -> Int {
        for r in parsed.rows {
            let lesson = Lesson(name: r.name, subject: r.subject, group: r.group, subheading: r.subheading, writeUp: r.writeUp)
            context.insert(lesson)
        }
        try context.save()
        return parsed.rows.count
    }

    // MARK: - Helpers
    /// RFC4180-ish CSV parser: returns array of records, each record is array of fields.
    private static func splitCSVIntoRecords(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            records.append(row)
            row = []
        }

        while i < text.endIndex {
            let c = text[i]
            if c == "\"" {
                if inQuotes {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if c == "," && !inQuotes {
                endField()
            } else if (c == "\n" || c == "\r") && !inQuotes {
                endField()
                endRow()
                if c == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" { i = next }
                }
            } else {
                field.append(c)
            }
            i = text.index(after: i)
        }

        // Flush last field/row if any content
        endField()
        if !row.isEmpty { endRow() }

        return records
    }

    /// Map header names to canonical keys using synonyms; requires name and subject.
    private static func mapHeaders(_ header: [String], synonyms: [String: [String]]) throws -> [String: Int] {
        var lowerMap: [String: Int] = [:]
        for (i, h) in header.enumerated() { lowerMap[h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = i }

        func findIndex(for keys: [String]) -> Int? {
            for k in keys { if let idx = lowerMap[k.lowercased()] { return idx } }
            return nil
        }

        guard let nameIndex = findIndex(for: synonyms["name"] ?? []),
              let subjectIndex = findIndex(for: synonyms["subject"] ?? []) else {
            throw ImportError.missingHeader("Name/Subject")
        }

        var result: [String: Int] = ["name": nameIndex, "subject": subjectIndex]
        if let idx = findIndex(for: synonyms["group"] ?? []) { result["group"] = idx }
        if let idx = findIndex(for: synonyms["subheading"] ?? []) { result["subheading"] = idx }
        if let idx = findIndex(for: synonyms["writeup"] ?? []) { result["writeup"] = idx }
        return result
    }
}
