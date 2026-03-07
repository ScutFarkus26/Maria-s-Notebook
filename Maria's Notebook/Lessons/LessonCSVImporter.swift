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
        var orderInGroup: Int?
        var materials: String
        var purpose: String
        var ageRange: String
        var teacherNotes: String
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
    static func importLessons(
        from data: Data, existingLessons: [Lesson], into context: ModelContext
    ) throws -> Summary {
        let parsed = try parse(data: data, existingLessons: existingLessons)
        let inserted = try commit(parsed: parsed, into: context, existingLessons: existingLessons)
        return Summary(
            totalRows: parsed.totalRows,
            insertedCount: inserted,
            potentialDuplicates: parsed.potentialDuplicates,
            warnings: parsed.warnings
        )
    }

    /// Parse CSV into rows and detect potential duplicates against existing lessons.
    static func parse(data: Data, existingLessons: [Lesson]) throws -> Parsed {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError.encoding("Unsupported text encoding; please use UTF-8.")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        let existingKeys: Set<String> = Set(existingLessons.map { duplicateKey(for: $0) })
        let result = try parseCSVRows(text: text, existingKeys: existingKeys)
        return Parsed(
            rows: result.rows, totalRows: result.rows.count,
            potentialDuplicates: result.duplicates, warnings: result.warnings
        )
    }

    /// Parse CSV into rows and detect potential duplicates against an existing set of duplicate keys.
    /// This overload avoids referencing main-actor isolated SwiftData model types so it can be used off the main actor.
    static func parse(data: Data, existingLessonKeys: Set<String>) throws -> Parsed {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError.encoding("Unsupported text encoding; please use UTF-8.")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        let result = try parseCSVRows(text: text, existingKeys: existingLessonKeys)
        return Parsed(
            rows: result.rows, totalRows: result.rows.count,
            potentialDuplicates: result.duplicates, warnings: result.warnings
        )
    }

    /// Commit parsed rows by inserting new Lesson objects; updates existing lessons if duplicates found.
    static func commit(parsed: Parsed, into context: ModelContext, existingLessons: [Lesson]) throws -> Int {
        var byKey: [String: Lesson] = [:]
        var maxOrderByGroup: [String: Int] = [:]
        for lesson in existingLessons {
            byKey[duplicateKey(for: lesson)] = lesson
            let groupKey = "\(lesson.subject)|\(lesson.group)"
            if lesson.orderInGroup > (maxOrderByGroup[groupKey] ?? -1) {
                maxOrderByGroup[groupKey] = lesson.orderInGroup
            }
        }
        var inserted = 0
        var updated = 0
        for r in parsed.rows {
            let key = duplicateKey(name: r.name, subject: r.subject, group: r.group)
            if let existingLesson = byKey[key] {
                if updateExistingLesson(existingLesson, with: r) { updated += 1 }
            } else {
                let groupKey = "\(r.subject)|\(r.group)"
                let order = nextInsertOrder(
                    groupKey: groupKey, explicit: r.orderInGroup, maxOrderByGroup: &maxOrderByGroup
                )
                let lesson = Lesson(
                    name: r.name, subject: r.subject, group: r.group,
                    subheading: r.subheading, writeUp: r.writeUp,
                    materials: r.materials, purpose: r.purpose,
                    ageRange: r.ageRange, teacherNotes: r.teacherNotes
                )
                lesson.orderInGroup = order
                context.insert(lesson)
                byKey[key] = lesson
                inserted += 1
            }
        }
        try context.save()
        return inserted
    }
}

// MARK: - Helpers

private struct CSVParseResult {
    let rows: [LessonCSVImporter.Row]
    let duplicates: [String]
    let warnings: [String]
}

extension LessonCSVImporter {
    // swiftlint:disable:next function_body_length
    private static func parseCSVRows(text: String, existingKeys: Set<String>) throws -> CSVParseResult {
        let records = try splitCSVIntoRecords(text)
        guard let header = records.first else { throw ImportError.empty }
        let synonyms: [String: [String]] = [
            "name": ["name", "lesson", "title"],
            "subject": ["subject"],
            "group": ["group", "category"],
            "subheading": ["subheading", "subtitle"],
            "writeup": ["writeup", "write up", "notes", "description"],
            "grouporder": ["grouporder", "group order", "order", "group position", "groupindex", "group index"],
            "materials": ["materials", "material"],
            "purpose": ["purpose", "objective", "learning objective"],
            "agerange": ["agerange", "age range", "age", "ages"],
            "teachernotes": ["teachernotes", "teacher notes", "teacher note"]
        ]
        let headerMap = try mapHeaders(header, synonyms: synonyms)
        var rows: [Row] = []
        var potentialDupTitles: [String] = []
        var warnings: [String] = []
        for (i, record) in records.dropFirst().enumerated() {
            if record.allSatisfy({ $0.trimmed().isEmpty }) { continue }
            func value(_ key: String) -> String {
                if let idx = headerMap[key], idx < record.count { return record[idx] } else { return "" }
            }
            let name = value("name").trimmed()
            let subject = value("subject").trimmed()
            if name.isEmpty || subject.isEmpty {
                warnings.append("Row \(i + 2): Missing required Name or Subject; row skipped.")
                continue
            }
            let groupOrderStr = value("grouporder").trimmed()
            var orderInGroup: Int?
            if !groupOrderStr.isEmpty {
                if let parsedInt = Int(groupOrderStr), parsedInt >= 0 {
                    orderInGroup = parsedInt
                } else {
                    warnings.append("Row \(i + 2): Invalid Group Order '\(groupOrderStr)'; ignored.")
                }
            }
            rows.append(Row(
                name: name, subject: subject, group: value("group").trimmed(),
                subheading: value("subheading").trimmed(), writeUp: value("writeup").trimmed(),
                orderInGroup: orderInGroup, materials: value("materials").trimmed(),
                purpose: value("purpose").trimmed(), ageRange: value("agerange").trimmed(),
                teacherNotes: value("teachernotes").trimmed()
            ))
            let key = duplicateKey(name: name, subject: subject, group: value("group").trimmed())
            if existingKeys.contains(key) {
                potentialDupTitles.append(LessonFormatter.duplicateDetectionTitle(
                    name: name, subject: subject, group: value("group").trimmed()
                ))
            }
        }
        return CSVParseResult(rows: rows, duplicates: potentialDupTitles.removingDuplicates(), warnings: warnings)
    }

    private static func updateExistingLesson(_ existing: Lesson, with row: Row) -> Bool {
        var changed = false
        if !row.subheading.isEmpty && row.subheading != existing.subheading {
            existing.subheading = row.subheading; changed = true
        }
        if !row.writeUp.isEmpty && row.writeUp != existing.writeUp {
            existing.writeUp = row.writeUp; changed = true
        }
        if let newOrder = row.orderInGroup, existing.orderInGroup != newOrder {
            existing.orderInGroup = newOrder; changed = true
        }
        if !row.materials.isEmpty && row.materials != existing.materials {
            existing.materials = row.materials; changed = true
        }
        if !row.purpose.isEmpty && row.purpose != existing.purpose {
            existing.purpose = row.purpose; changed = true
        }
        if !row.ageRange.isEmpty && row.ageRange != existing.ageRange {
            existing.ageRange = row.ageRange; changed = true
        }
        if !row.teacherNotes.isEmpty && row.teacherNotes != existing.teacherNotes {
            existing.teacherNotes = row.teacherNotes; changed = true
        }
        return changed
    }

    private static func nextInsertOrder(groupKey: String, explicit: Int?, maxOrderByGroup: inout [String: Int]) -> Int {
        if let order = explicit {
            let current = maxOrderByGroup[groupKey] ?? -1
            if order > current { maxOrderByGroup[groupKey] = order }
            return order
        }
        let next = (maxOrderByGroup[groupKey] ?? -1) + 1
        maxOrderByGroup[groupKey] = next
        return next
    }

    // MARK: - CSV Parsing
    // RFC4180-ish CSV parser: returns array of records, each record is array of fields.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        // Flush last field/row if appropriate
        if inQuotes {
            // Unterminated quote: treat as end of field/row anyway
            endField()
            if !row.isEmpty { endRow() }
        } else {
            // Only append if there was any data in the current field or row
            if !field.isEmpty || !row.isEmpty {
                endField()
                endRow()
            }
        }

        return records
    }

    /// Map header names to canonical keys using synonyms; requires name and subject.
    private static func mapHeaders(_ header: [String], synonyms: [String: [String]]) throws -> [String: Int] {
        let mapping = CSVHeaderMapping.buildMapping(headers: header, synonymMap: synonyms)
        
        // Validate required headers
        guard mapping["name"] != nil, mapping["subject"] != nil else {
            throw ImportError.missingHeader("Name/Subject")
        }
        
        return mapping
    }

    /// Normalize and combine name, subject, group to form a duplicate detection key.
    private static func duplicateKey(name: String, subject: String, group: String) -> String {
        let n = normalizeComponent(name)
        let s = normalizeComponent(subject)
        let g = normalizeComponent(group)
        return [n, s, g].joined(separator: "|")
    }
    /// Normalize a component string by trimming, lowercasing, removing diacritics and collapsing whitespace.
    private static func normalizeComponent(_ s: String) -> String {
        StringNormalization.normalizeComponent(s)
    }

    /// Compute duplicate key for a lesson.
    static func duplicateKey(for lesson: Lesson) -> String {
        duplicateKey(name: lesson.name, subject: lesson.subject, group: lesson.group)
    }
}
