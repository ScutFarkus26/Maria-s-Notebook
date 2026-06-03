import Foundation
import CoreData

// A CSV importer for CDLesson records that supports parse-first and commit-later workflows.
enum LessonCSVImporter {
    // MARK: - Row DTO
    struct Row {
        var name: String
        var area: String
        var sequence: String
        var section: String
        var writeUp: String
        var orderInSequence: Int?
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
        from data: Data, existingLessons: [CDLesson], into context: NSManagedObjectContext
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
    static func parse(data: Data, existingLessons: [CDLesson]) throws -> Parsed {
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

    /// Commit parsed rows by inserting new CDLesson objects; updates existing lessons if duplicates found.
    static func commit(
        parsed: Parsed,
        into context: NSManagedObjectContext,
        existingLessons: [CDLesson]
    ) throws -> Int {
        var byKey: [String: CDLesson] = [:]
        var maxOrderBySequence: [String: Int] = [:]
        for lesson in existingLessons {
            byKey[duplicateKey(for: lesson)] = lesson
            let sequenceKey = "\(lesson.area)|\(lesson.sequence)"
            let orderInt = Int(lesson.orderInSequence)
            if orderInt > (maxOrderBySequence[sequenceKey] ?? -1) {
                maxOrderBySequence[sequenceKey] = orderInt
            }
        }
        var inserted = 0
        var updated = 0
        for r in parsed.rows {
            let key = duplicateKey(name: r.name, area: r.area, sequence: r.sequence)
            if let existingLesson = byKey[key] {
                if updateExistingLesson(existingLesson, with: r) { updated += 1 }
            } else {
                let sequenceKey = "\(r.area)|\(r.sequence)"
                let order = nextInsertOrder(
                    sequenceKey: sequenceKey, explicit: r.orderInSequence, maxOrderBySequence: &maxOrderBySequence
                )
                let lesson = CDLesson(context: context)
                lesson.name = r.name
                lesson.area = r.area
                lesson.sequence = r.sequence
                lesson.section = r.section
                lesson.writeUp = r.writeUp
                lesson.materials = r.materials
                lesson.purpose = r.purpose
                lesson.ageRange = r.ageRange
                lesson.teacherNotes = r.teacherNotes
                lesson.orderInSequence = Int64(order)
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
            "area": ["area"],
            "sequence": ["sequence", "category"],
            "section": ["section", "subtitle"],
            "writeup": ["writeup", "write up", "notes", "description"],
            "sequenceorder": [
                "sequenceorder", "sequence order", "order", "sequence position", "sequenceindex", "sequence index"
            ],
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
            let area = value("area").trimmed()
            if name.isEmpty || area.isEmpty {
                warnings.append("Row \(i + 2): Missing required Name or Area; row skipped.")
                continue
            }
            let sequenceOrderStr = value("sequenceorder").trimmed()
            var orderInSequence: Int?
            if !sequenceOrderStr.isEmpty {
                if let parsedInt = Int(sequenceOrderStr), parsedInt >= 0 {
                    orderInSequence = parsedInt
                } else {
                    warnings.append("Row \(i + 2): Invalid Sequence Order '\(sequenceOrderStr)'; ignored.")
                }
            }
            rows.append(Row(
                name: name, area: area, sequence: value("sequence").trimmed(),
                section: value("section").trimmed(), writeUp: value("writeup").trimmed(),
                orderInSequence: orderInSequence, materials: value("materials").trimmed(),
                purpose: value("purpose").trimmed(), ageRange: value("agerange").trimmed(),
                teacherNotes: value("teachernotes").trimmed()
            ))
            let key = duplicateKey(name: name, area: area, sequence: value("sequence").trimmed())
            if existingKeys.contains(key) {
                potentialDupTitles.append(LessonFormatter.duplicateDetectionTitle(
                    name: name, area: area, sequence: value("sequence").trimmed()
                ))
            }
        }
        return CSVParseResult(rows: rows, duplicates: potentialDupTitles.removingDuplicates(), warnings: warnings)
    }

    private static func updateExistingLesson(_ existing: CDLesson, with row: Row) -> Bool {
        var changed = false
        if !row.section.isEmpty && row.section != existing.section {
            existing.section = row.section; changed = true
        }
        if !row.writeUp.isEmpty && row.writeUp != existing.writeUp {
            existing.writeUp = row.writeUp; changed = true
        }
        if let newOrder = row.orderInSequence, existing.orderInSequence != Int64(newOrder) {
            existing.orderInSequence = Int64(newOrder); changed = true
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

    private static func nextInsertOrder(
        sequenceKey: String,
        explicit: Int?,
        maxOrderBySequence: inout [String: Int]
    ) -> Int {
        if let order = explicit {
            let current = maxOrderBySequence[sequenceKey] ?? -1
            if order > current { maxOrderBySequence[sequenceKey] = order }
            return order
        }
        let next = (maxOrderBySequence[sequenceKey] ?? -1) + 1
        maxOrderBySequence[sequenceKey] = next
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

    /// Map header names to canonical keys using synonyms; requires name and area.
    private static func mapHeaders(_ header: [String], synonyms: [String: [String]]) throws -> [String: Int] {
        let mapping = CSVHeaderMapping.buildMapping(headers: header, synonymMap: synonyms)
        
        // Validate required headers
        guard mapping["name"] != nil, mapping["area"] != nil else {
            throw ImportError.missingHeader("Name/Area")
        }
        
        return mapping
    }

    /// Normalize and combine name, area, sequence to form a duplicate detection key.
    private static func duplicateKey(name: String, area: String, sequence: String) -> String {
        let n = normalizeComponent(name)
        let s = normalizeComponent(area)
        let g = normalizeComponent(sequence)
        return [n, s, g].joined(separator: "|")
    }
    /// Normalize a component string by trimming, lowercasing, removing diacritics and collapsing whitespace.
    private static func normalizeComponent(_ s: String) -> String {
        StringNormalization.normalizeComponent(s)
    }

    /// Compute duplicate key for a lesson.
    static func duplicateKey(for lesson: CDLesson) -> String {
        duplicateKey(name: lesson.name, area: lesson.area, sequence: lesson.sequence)
    }
}
