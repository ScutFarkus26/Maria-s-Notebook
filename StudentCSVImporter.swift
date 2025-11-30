import Foundation
import SwiftData

// A CSV importer for Student records with parse-first, map-then-commit workflow.
enum StudentCSVImporter {
    // MARK: - Row DTO
    struct Row: Identifiable, Hashable {
        let id = UUID()
        var firstName: String
        var lastName: String
        var birthday: Date?
        var dateStarted: Date?
        var level: Student.Level?
    }

    // MARK: - Parsed (dry run)
    struct Parsed: Identifiable {
        let id = UUID()
        let rows: [Row]
        let totalRows: Int
        let potentialDuplicates: [String] // display names
        let warnings: [String]
    }

    // MARK: - Summary (post-commit)
    struct Summary {
        let totalRows: Int
        let insertedCount: Int
        let updatedCount: Int
        let potentialDuplicates: [String]
        let warnings: [String]
    }

    // MARK: - Errors
    enum ImportError: Error, LocalizedError {
        case empty
        case needsMapping
        case malformedRow(Int)
        case missingRequired(String)
        case encoding(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The file appears to be empty."
            case .needsMapping:
                return "Column mapping required. Please map CSV headers to student fields."
            case .malformedRow(let n):
                return "Malformed row at line \(n)."
            case .missingRequired(let what):
                return "Missing required value: \(what)."
            case .encoding(let msg):
                return msg
            }
        }
    }

    // MARK: - Mapping
    struct Mapping {
        var firstName: Int?
        var lastName: Int?
        var fullName: Int?
        var birthday: Int?
        var startDate: Int?
        var level: Int?
        var splitFullNameOn: String = " "
    }

    static func detectMapping(headers: [String]) -> Mapping {
        var map = Mapping()
        let lower = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        func find(_ candidates: [String]) -> Int? {
            for c in candidates {
                if let idx = lower.firstIndex(of: c) { return idx }
            }
            return nil
        }

        let firstSyn = ["first name", "firstname", "given name", "givenname", "first"]
        let lastSyn = ["last name", "lastname", "family name", "surname", "last"]
        let fullSyn = ["name", "full name", "fullname", "student", "student name"]
        let dobSyn = ["birthday", "birth date", "birthdate", "dob", "date of birth"]
        let startSyn = ["start date", "date started", "start", "started"]
        let levelSyn = ["level", "grade", "class"]

        map.firstName = find(firstSyn)
        map.lastName = find(lastSyn)
        map.fullName = find(fullSyn)
        map.birthday = find(dobSyn)
        map.startDate = find(startSyn)
        map.level = find(levelSyn)
        return map
    }

    // MARK: - Public API
    static func parse(data: Data, mapping: Mapping?, existingStudents: [Student]) throws -> Parsed {
        guard let csv = CSVParser.parse(data: data) else {
            throw ImportError.encoding("Unsupported text encoding; please use UTF-8.")
        }
        let headers = csv.headers
        var useMap = mapping ?? detectMapping(headers: headers)
        // Require either First+Last or Full Name
        let hasFirstLast = (useMap.firstName != nil) && (useMap.lastName != nil)
        let hasFull = (useMap.fullName != nil)
        if !hasFirstLast && !hasFull { throw ImportError.needsMapping }

        // Existing keys for duplicate detection
        let existingKeys: Set<String> = Set(existingStudents.map { duplicateKey(for: $0) })
        let existingNameKeys: Set<String> = Set(existingStudents.map { ("\($0.firstName) \($0.lastName)".normalizedNameKey()) })

        var rows: [Row] = []
        var potentialDupNames: [String] = []
        var warnings: [String] = []

        for (i, rawRow) in csv.rows.enumerated() {
            // Extract text safely
            func value(_ idx: Int?) -> String {
                guard let idx, idx >= 0, idx < rawRow.count else { return "" }
                return rawRow[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var first = ""
            var last = ""
            if hasFirstLast {
                first = value(useMap.firstName)
                last = value(useMap.lastName)
            } else if hasFull {
                let full = value(useMap.fullName)
                let parts = full.split(separator: Character(useMap.splitFullNameOn), omittingEmptySubsequences: true)
                if parts.count > 0 { first = String(parts[0]) }
                if parts.count > 1 { last = parts.dropFirst().joined(separator: " ") }
            }
            first = first.trimmingCharacters(in: .whitespacesAndNewlines)
            last = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if first.isEmpty || last.isEmpty {
                warnings.append("Row \(i + 2): Missing first or last name; row skipped.")
                continue
            }

            let bdayStr = value(useMap.birthday)
            let startStr = value(useMap.startDate)
            let levelStr = value(useMap.level)

            let bday = DateParser.parse(bdayStr)
            let start = DateParser.parse(startStr)
            let lvl = parseLevel(from: levelStr)

            let row = Row(firstName: first, lastName: last, birthday: bday, dateStarted: start, level: lvl)
            rows.append(row)

            let key = duplicateKey(first: first, last: last, birthday: bday)
            var isPotentialDuplicate = false
            if existingKeys.contains(key) {
                isPotentialDuplicate = true
            } else if bday == nil {
                let nameKey = "\(first) \(last)".normalizedNameKey()
                if existingNameKeys.contains(nameKey) {
                    isPotentialDuplicate = true
                }
            }
            if isPotentialDuplicate {
                let display = "\(first) \(last)"
                potentialDupNames.append(display)
            }
        }

        // Deduplicate duplicate names for display while preserving order
        var seen: Set<String> = []
        let dedupedPotential = potentialDupNames.filter { seen.insert($0).inserted }

        return Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: dedupedPotential, warnings: warnings)
    }

    static func commit(parsed: Parsed, into context: ModelContext, existingStudents: [Student]) throws -> Summary {
        var inserted = 0
        var updated = 0
        // Index existing by duplicate key and by name-only key
        var byFullKey: [String: Student] = [:]
        var byNameKey: [String: Student] = [:]
        for s in existingStudents {
            let full = duplicateKey(for: s)
            if byFullKey[full] == nil { byFullKey[full] = s }
            let nameKey = "\(s.firstName) \(s.lastName)".normalizedNameKey()
            if byNameKey[nameKey] == nil { byNameKey[nameKey] = s }
        }

        for r in parsed.rows {
            let hasBirthday = (r.birthday != nil)

            if hasBirthday {
                let key = duplicateKey(first: r.firstName, last: r.lastName, birthday: r.birthday)
                if let existing = byFullKey[key] {
                    var didChange = false
                    if existing.birthday == nil, let b = r.birthday { existing.birthday = b; didChange = true }
                    if existing.dateStarted == nil, let ds = r.dateStarted { existing.dateStarted = ds; didChange = true }
                    if let lvl = r.level, existing.level != lvl { existing.level = lvl; didChange = true }
                    if didChange { updated += 1 }
                    continue
                }
            } else {
                let nameKey = "\(r.firstName) \(r.lastName)".normalizedNameKey()
                if let existing = byNameKey[nameKey] {
                    var didChange = false
                    if existing.dateStarted == nil, let ds = r.dateStarted { existing.dateStarted = ds; didChange = true }
                    if let lvl = r.level, existing.level != lvl { existing.level = lvl; didChange = true }
                    if didChange { updated += 1 }
                    continue
                }
            }

            // No match found; insert new student
            let student = Student(
                firstName: r.firstName,
                lastName: r.lastName,
                birthday: r.birthday ?? Date(),
                level: r.level ?? .lower,
                dateStarted: r.dateStarted
            )
            context.insert(student)
            inserted += 1

            // Update indexes so subsequent rows can merge into this newly created student
            let newFullKey = duplicateKey(first: r.firstName, last: r.lastName, birthday: r.birthday ?? student.birthday)
            byFullKey[newFullKey] = student
            let newNameKey = "\(r.firstName) \(r.lastName)".normalizedNameKey()
            if byNameKey[newNameKey] == nil { byNameKey[newNameKey] = student }
        }
        try context.save()
        return Summary(totalRows: parsed.totalRows, insertedCount: inserted, updatedCount: updated, potentialDuplicates: parsed.potentialDuplicates, warnings: parsed.warnings)
    }

    // MARK: - Helpers
    static func duplicateKey(for student: Student) -> String {
        duplicateKey(first: student.firstName, last: student.lastName, birthday: student.birthday)
    }

    static func duplicateKey(first: String, last: String, birthday: Date?) -> String {
        let nameKey = "\(first) \(last)".normalizedNameKey()
        if let b = birthday {
            let fmt = DateFormatter()
            fmt.calendar = Calendar(identifier: .iso8601)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.dateFormat = "yyyy-MM-dd"
            let d = fmt.string(from: b)
            return nameKey + "|" + d
        }
        return nameKey
    }

    static func parseLevel(from string: String) -> Student.Level? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "lower", "l", "lower elementary", "lower el", "lower elem":
            return .lower
        case "upper", "u", "upper elementary", "upper el", "upper elem":
            return .upper
        default:
            return nil
        }
    }
}

