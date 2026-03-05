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
    static func importLessons(from data: Data, existingLessons: [Lesson], into context: ModelContext) throws -> Summary {
        let parsed = try parse(data: data, existingLessons: existingLessons)
        let inserted = try commit(parsed: parsed, into: context, existingLessons: existingLessons)
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
            "writeup": ["writeup", "write up", "notes", "description"],
            "grouporder": ["grouporder", "group order", "order", "group position", "groupindex", "group index"],
            "materials": ["materials", "material"],
            "purpose": ["purpose", "objective", "learning objective"],
            "agerange": ["agerange", "age range", "age", "ages"],
            "teachernotes": ["teachernotes", "teacher notes", "teacher note"]
        ]

        let headerMap = try mapHeaders(header, synonyms: synonyms)

        // Build existing keys for duplicate detection
        let existingKeys: Set<String> = Set(existingLessons.map { duplicateKey(for: $0) })

        var rows: [Row] = []
        var potentialDupTitles: [String] = []
        var warnings: [String] = []

        for (i, record) in records.dropFirst().enumerated() {
            // Tolerate blank lines
            if record.allSatisfy({ $0.trimmed().isEmpty }) { continue }

            func value(_ key: String) -> String {
                if let idx = headerMap[key], idx < record.count { return record[idx] } else { return "" }
            }

            let name = value("name").trimmed()
            let subject = value("subject").trimmed()
            let group = value("group").trimmed()
            let subheading = value("subheading").trimmed()
            let writeUp = value("writeup").trimmed()

            let groupOrderStr = value("grouporder").trimmed()
            var orderInGroup: Int?
            if !groupOrderStr.isEmpty {
                if let parsedInt = Int(groupOrderStr), parsedInt >= 0 {
                    orderInGroup = parsedInt
                } else {
                    warnings.append("Row \(i + 2): Invalid Group Order '\(groupOrderStr)'; ignored.")
                }
            }

            let materials = value("materials").trimmed()
            let purpose = value("purpose").trimmed()
            let ageRange = value("agerange").trimmed()
            let teacherNotes = value("teachernotes").trimmed()

            if name.isEmpty || subject.isEmpty {
                warnings.append("Row \(i + 2): Missing required Name or Subject; row skipped.")
                continue
            }

            let row = Row(name: name, subject: subject, group: group, subheading: subheading, writeUp: writeUp, orderInGroup: orderInGroup, materials: materials, purpose: purpose, ageRange: ageRange, teacherNotes: teacherNotes)
            rows.append(row)

            let key = duplicateKey(name: name, subject: subject, group: group)
            if existingKeys.contains(key) {
                let title = LessonFormatter.duplicateDetectionTitle(name: name, subject: subject, group: group)
                potentialDupTitles.append(title)
            }
        }

        // Deduplicate potentialDupTitles preserving order
        let uniquePotentialDupTitles = potentialDupTitles.removingDuplicates()

        return Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: uniquePotentialDupTitles, warnings: warnings)
    }

    /// Parse CSV into rows and detect potential duplicates against an existing set of duplicate keys.
    /// This overload avoids referencing main-actor isolated SwiftData model types so it can be used off the main actor.
    static func parse(data: Data, existingLessonKeys: Set<String>) throws -> Parsed {
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
            // Tolerate blank lines
            if record.allSatisfy({ $0.trimmed().isEmpty }) { continue }

            func value(_ key: String) -> String {
                if let idx = headerMap[key], idx < record.count { return record[idx] } else { return "" }
            }

            let name = value("name").trimmed()
            let subject = value("subject").trimmed()
            let group = value("group").trimmed()
            let subheading = value("subheading").trimmed()
            let writeUp = value("writeup").trimmed()

            let groupOrderStr = value("grouporder").trimmed()
            var orderInGroup: Int?
            if !groupOrderStr.isEmpty {
                if let parsedInt = Int(groupOrderStr), parsedInt >= 0 {
                    orderInGroup = parsedInt
                } else {
                    warnings.append("Row \(i + 2): Invalid Group Order '\(groupOrderStr)'; ignored.")
                }
            }

            let materials = value("materials").trimmed()
            let purpose = value("purpose").trimmed()
            let ageRange = value("agerange").trimmed()
            let teacherNotes = value("teachernotes").trimmed()

            if name.isEmpty || subject.isEmpty {
                warnings.append("Row \(i + 2): Missing required Name or Subject; row skipped.")
                continue
            }

            let row = Row(name: name, subject: subject, group: group, subheading: subheading, writeUp: writeUp, orderInGroup: orderInGroup, materials: materials, purpose: purpose, ageRange: ageRange, teacherNotes: teacherNotes)
            rows.append(row)

            let key = duplicateKey(name: name, subject: subject, group: group)
            if existingLessonKeys.contains(key) {
                let title = LessonFormatter.duplicateDetectionTitle(name: name, subject: subject, group: group)
                potentialDupTitles.append(title)
            }
        }

        // Deduplicate potentialDupTitles preserving order
        let uniquePotentialDupTitles = potentialDupTitles.removingDuplicates()

        return Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: uniquePotentialDupTitles, warnings: warnings)
    }

    /// Commit parsed rows by inserting new Lesson objects; updates existing lessons if duplicates found.
    static func commit(parsed: Parsed, into context: ModelContext, existingLessons: [Lesson]) throws -> Int {
        // Build a dictionary of existing lessons by duplicate key
        var byKey: [String: Lesson] = [:]
        for lesson in existingLessons {
            byKey[duplicateKey(for: lesson)] = lesson
        }

        // Build a map of max orderInGroup for each subject+group combination
        var maxOrderByGroup: [String: Int] = [:]
        for lesson in existingLessons {
            let groupKey = "\(lesson.subject)|\(lesson.group)"
            let current = maxOrderByGroup[groupKey] ?? -1
            if lesson.orderInGroup > current {
                maxOrderByGroup[groupKey] = lesson.orderInGroup
            }
        }

        var inserted = 0
        var updated = 0

        for r in parsed.rows {
            let key = duplicateKey(name: r.name, subject: r.subject, group: r.group)
            if let existingLesson = byKey[key] {
                var changed = false
                if !r.subheading.isEmpty && r.subheading != existingLesson.subheading {
                    existingLesson.subheading = r.subheading
                    changed = true
                }
                if !r.writeUp.isEmpty && r.writeUp != existingLesson.writeUp {
                    existingLesson.writeUp = r.writeUp
                    changed = true
                }
                if let newOrder = r.orderInGroup {
                    if existingLesson.orderInGroup != newOrder {
                        existingLesson.orderInGroup = newOrder
                        changed = true
                    }
                }
                if !r.materials.isEmpty && r.materials != existingLesson.materials {
                    existingLesson.materials = r.materials
                    changed = true
                }
                if !r.purpose.isEmpty && r.purpose != existingLesson.purpose {
                    existingLesson.purpose = r.purpose
                    changed = true
                }
                if !r.ageRange.isEmpty && r.ageRange != existingLesson.ageRange {
                    existingLesson.ageRange = r.ageRange
                    changed = true
                }
                if !r.teacherNotes.isEmpty && r.teacherNotes != existingLesson.teacherNotes {
                    existingLesson.teacherNotes = r.teacherNotes
                    changed = true
                }
                if changed {
                    updated += 1
                }
            } else {
                // Calculate the order for this new lesson
                let groupKey = "\(r.subject)|\(r.group)"
                let orderToUse: Int
                if let explicitOrder = r.orderInGroup {
                    // Use the explicit order from CSV, but also track it for subsequent lessons
                    orderToUse = explicitOrder
                    let currentMax = maxOrderByGroup[groupKey] ?? -1
                    if explicitOrder > currentMax {
                        maxOrderByGroup[groupKey] = explicitOrder
                    }
                } else {
                    // Auto-assign sequential order based on input position
                    let nextOrder = (maxOrderByGroup[groupKey] ?? -1) + 1
                    maxOrderByGroup[groupKey] = nextOrder
                    orderToUse = nextOrder
                }

                let lesson = Lesson(name: r.name, subject: r.subject, group: r.group, subheading: r.subheading, writeUp: r.writeUp, materials: r.materials, purpose: r.purpose, ageRange: r.ageRange, teacherNotes: r.teacherNotes)
                lesson.orderInGroup = orderToUse
                context.insert(lesson)
                byKey[key] = lesson
                inserted += 1
            }
        }
        try context.save()
        return inserted
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
