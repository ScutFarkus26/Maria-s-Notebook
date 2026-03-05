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
        
        let synonymMap: [String: [String]] = [
            "firstName": ["first name", "firstname", "given name", "givenname", "first"],
            "lastName": ["last name", "lastname", "family name", "surname", "last"],
            "fullName": ["name", "full name", "fullname", "student", "student name"],
            "birthday": ["birthday", "birth date", "birthdate", "dob", "date of birth"],
            "startDate": ["start date", "date started", "start", "started"],
            "level": ["level", "grade", "class"]
        ]
        
        let headerMapping = CSVHeaderMapping.buildMapping(headers: headers, synonymMap: synonymMap)
        
        map.firstName = headerMapping["firstName"]
        map.lastName = headerMapping["lastName"]
        map.fullName = headerMapping["fullName"]
        map.birthday = headerMapping["birthday"]
        map.startDate = headerMapping["startDate"]
        map.level = headerMapping["level"]
        
        return map
    }

    // MARK: - Public API
    static func parse(data: Data, mapping: Mapping?, existingStudents: [Student]) throws -> Parsed {
        // Existing keys for duplicate detection
        let existingKeys: Set<String> = Set(existingStudents.map { duplicateKey(for: $0) })
        let existingNameKeys: Set<String> = Set(existingStudents.map {
            ("\($0.firstName) \($0.lastName)".normalizedNameKey())
        })
        
        return try parse(
            data: data,
            mapping: mapping,
            existingFullKeys: existingKeys,
            existingNameKeys: existingNameKeys
        )
    }

    /// Parse CSV into rows and detect potential duplicates using precomputed keys.
    /// This overload avoids referencing SwiftData model values so it can be used from a background task safely.
    static func parse(
        data: Data, mapping: Mapping?,
        existingFullKeys: Set<String>,
        existingNameKeys: Set<String>
    ) throws -> Parsed {
        guard let csv = CSVParser.parse(data: data) else {
            throw ImportError.encoding("Unsupported text encoding; please use UTF-8.")
        }
        let headers = csv.headers
        let useMap = mapping ?? detectMapping(headers: headers)
        // Require either First+Last or Full Name
        let hasFirstLast = (useMap.firstName != nil) && (useMap.lastName != nil)
        let hasFull = (useMap.fullName != nil)
        if !hasFirstLast && !hasFull { throw ImportError.needsMapping }

        var rows: [Row] = []
        var potentialDupNames: [String] = []
        var warnings: [String] = []

        for (i, rawRow) in csv.rows.enumerated() {
            // Extract text safely
            func value(_ idx: Int?) -> String {
                guard let idx, idx >= 0, idx < rawRow.count else { return "" }
                return rawRow[idx].trimmed()
            }

            // Parse name fields
            let (first, last) = parseNameFields(
                from: rawRow,
                mapping: useMap,
                hasFirstLast: hasFirstLast,
                hasFull: hasFull,
                value: value
            )
            
            guard !first.isEmpty && !last.isEmpty else {
                warnings.append("Row \(i + 2): Missing first or last name; row skipped.")
                continue
            }

            // Parse other fields
            let bdayStr = value(useMap.birthday)
            let startStr = value(useMap.startDate)
            let levelStr = value(useMap.level)

            let bday = DateParser.parse(bdayStr)
            let start = DateParser.parse(startStr)
            let lvl = parseLevel(from: levelStr)

            let row = Row(firstName: first, lastName: last, birthday: bday, dateStarted: start, level: lvl)
            rows.append(row)

            // Check for duplicates
            if isDuplicate(
                first: first, last: last, birthday: bday,
                existingFullKeys: existingFullKeys,
                existingNameKeys: existingNameKeys
            ) {
                potentialDupNames.append("\(first) \(last)")
            }
        }

        // Deduplicate duplicate names for display while preserving order
        let dedupedPotential = potentialDupNames.removingDuplicates()

        return Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: dedupedPotential, warnings: warnings)
    }
    
    // MARK: - Private Helpers
    
    /// Parses first and last name from CSV row based on mapping configuration.
    private static func parseNameFields(
        from rawRow: [String],
        mapping: Mapping,
        hasFirstLast: Bool,
        hasFull: Bool,
        value: (Int?) -> String
    ) -> (first: String, last: String) {
        var first = ""
        var last = ""
        
        if hasFirstLast {
            first = value(mapping.firstName)
            last = value(mapping.lastName)
        } else if hasFull {
            let full = value(mapping.fullName)
            let parts = full.split(separator: Character(mapping.splitFullNameOn), omittingEmptySubsequences: true)
            if !parts.isEmpty { first = String(parts[0]) }
            if parts.count > 1 { last = parts.dropFirst().joined(separator: " ") }
        }
        
        first = first.trimmed()
        last = last.trimmed()
        
        return (first, last)
    }
    
    /// Checks if a student row is a potential duplicate based on existing keys.
    private static func isDuplicate(
        first: String,
        last: String,
        birthday: Date?,
        existingFullKeys: Set<String>,
        existingNameKeys: Set<String>
    ) -> Bool {
        let fullKey = duplicateKey(first: first, last: last, birthday: birthday)
        let nameKey = "\(first) \(last)".normalizedNameKey()
        return CSVDuplicateDetection.isDuplicate(
            fullKey: fullKey,
            nameKey: nameKey,
            existingFullKeys: existingFullKeys,
            existingNameKeys: existingNameKeys,
            hasFullKey: birthday != nil
        )
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
                    if let b = r.birthday, existing.birthday != b {
                        existing.birthday = b; didChange = true
                    }
                    if existing.dateStarted == nil, let ds = r.dateStarted {
                        existing.dateStarted = ds; didChange = true
                    }
                    if let lvl = r.level, existing.level != lvl {
                        existing.level = lvl; didChange = true
                    }
                    if didChange { updated += 1 }
                    continue
                }
            } else {
                let nameKey = "\(r.firstName) \(r.lastName)".normalizedNameKey()
                if let existing = byNameKey[nameKey] {
                    var didChange = false
                    if let b = r.birthday, existing.birthday != b {
                        existing.birthday = b; didChange = true
                    }
                    if existing.dateStarted == nil, let ds = r.dateStarted {
                        existing.dateStarted = ds; didChange = true
                    }
                    if let lvl = r.level, existing.level != lvl {
                        existing.level = lvl; didChange = true
                    }
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
            let newFullKey = duplicateKey(
                first: r.firstName, last: r.lastName,
                birthday: r.birthday ?? student.birthday
            )
            byFullKey[newFullKey] = student
            let newNameKey = "\(r.firstName) \(r.lastName)".normalizedNameKey()
            if byNameKey[newNameKey] == nil { byNameKey[newNameKey] = student }
        }
        try context.save()
        return Summary(
            totalRows: parsed.totalRows,
            insertedCount: inserted,
            updatedCount: updated,
            potentialDuplicates: parsed.potentialDuplicates,
            warnings: parsed.warnings
        )
    }

    // MARK: - Helpers
    private static let isoDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .iso8601)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    static func duplicateKey(for student: Student) -> String {
        duplicateKey(first: student.firstName, last: student.lastName, birthday: student.birthday)
    }

    static func duplicateKey(first: String, last: String, birthday: Date?) -> String {
        let nameKey = "\(first) \(last)".normalizedNameKey()
        if let b = birthday {
            let d = isoDayFormatter.string(from: b)
            return nameKey + "|" + d
        }
        return nameKey
    }

    static func parseLevel(from string: String) -> Student.Level? {
        let s = string.normalizedForComparison()
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
