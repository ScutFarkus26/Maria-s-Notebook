import Foundation
import CoreData

// A CSV importer for CDStudent records with parse-first, map-then-commit workflow.
enum StudentCSVImporter {
    // MARK: - Row DTO
    struct Row: Identifiable, Hashable {
        let id = UUID()
        var firstName: String
        var lastName: String
        var birthday: Date?
        var dateStarted: Date?
        var level: CDStudent.Level?
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
        /// Rows written nowhere: the class already has a student by that name
        /// whose birthday differs, or more than one, so the row can't be told
        /// apart from a duplicate. Display names.
        var skippedDuplicates: [String] = []
    }

    // MARK: - Errors
    /// Why a spreadsheet couldn't be read. Each description is what the
    /// guide sees in the "Couldn't Import Students" alert.
    enum ImportError: Error, LocalizedError, Equatable {
        /// The app wasn't given access to the chosen file.
        case cantOpen
        /// The file's text isn't in an encoding the parser reads.
        case unreadableText
        /// No column was matched to the students' names.
        case needsMapping

        var errorDescription: String? {
            switch self {
            case .cantOpen:
                return "Couldn't open that file. Choose it again and try once more."
            case .unreadableText:
                return "This file's text can't be read. In your spreadsheet app, "
                    + "save it as \u{201C}CSV UTF-8\u{201D} and try again."
            case .needsMapping:
                return "Choose which column has the students' names "
                    + "(First and Last Name, or Full Name), then try again."
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

    /// The column names the importer recognizes, by field.
    static let synonymMap: [String: [String]] = [
        "firstName": ["first name", "firstname", "given name", "givenname", "first"],
        "lastName": ["last name", "lastname", "family name", "surname", "last"],
        "fullName": ["name", "full name", "fullname", "student", "student name"],
        "birthday": ["birthday", "birth date", "birthdate", "dob", "date of birth"],
        "startDate": ["start date", "date started", "start", "started"],
        "level": ["level", "grade", "class"]
    ]

    /// Whether a file's first row is its header: it names at least one
    /// column the importer knows. Such a row is the header even with a blank
    /// or repeated cell.
    static func looksLikeHeaderRow(_ cells: [String]) -> Bool {
        let known = Set(synonymMap.values.joined())
        return cells.contains { known.contains($0.normalizedForComparison()) }
    }

    /// The spreadsheet as a table, its first row read as the header whenever
    /// it names a known column.
    static func readTable(_ data: Data) -> CSVData? {
        CSVParser.parse(data: data, headerRow: looksLikeHeaderRow)
    }

    static func detectMapping(headers: [String]) -> Mapping {
        var map = Mapping()

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

    /// Parse CSV into rows and detect potential duplicates using precomputed keys.
    /// This overload avoids referencing SwiftData model values so it can be used from a background task safely.
    static func parse(
        data: Data, mapping: Mapping?,
        existingFullKeys: Set<String>,
        existingNameKeys: Set<String>
    ) throws -> Parsed {
        guard let csv = readTable(data) else {
            throw ImportError.unreadableText
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
            // The spreadsheet's own line, past any blank lines left out.
            let line = csv.recordNumbers.flatMap { i < $0.count ? $0[i] : nil } ?? i + 2

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
                warnings.append("Line \(line) skipped: it's missing a first or last name.")
                continue
            }

            // Parse other fields
            let bdayStr = value(useMap.birthday)
            let startStr = value(useMap.startDate)
            let levelStr = value(useMap.level)

            let bday = date(bdayStr, named: "birthday", line: line, warnings: &warnings)
            let start = date(startStr, named: "start date", line: line, warnings: &warnings)
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

    /// A date cell's value, or nil with a warning naming the line when the
    /// cell held something that isn't a date the importer takes.
    private static func date(_ text: String, named field: String, line: Int, warnings: inout [String]) -> Date? {
        switch DateParser.outcome(text) {
        case .empty:
            return nil
        case .date(let date):
            return date
        case .tooEarly:
            warnings.append(
                "Line \(line): the \(field) \u{201C}\(text)\u{201D} is before 1900, so it was left out. "
                    + "Check it in the spreadsheet."
            )
            return nil
        case .unreadable:
            warnings.append(
                "Line \(line): couldn\u{2019}t read the \(field) \u{201C}\(text)\u{201D}, so it was left out."
            )
            return nil
        }
    }

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
            if let comma = full.firstIndex(of: ",") {
                // "Smith, Maya": family name first.
                last = String(full[..<comma])
                first = String(full[full.index(after: comma)...])
            } else {
                let parts = full.split(separator: Character(mapping.splitFullNameOn), omittingEmptySubsequences: true)
                if !parts.isEmpty { first = String(parts[0]) }
                if parts.count > 1 { last = parts.dropFirst().joined(separator: " ") }
            }
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
        CSVDuplicateDetection.isDuplicate(
            fullKey: duplicateKey(first: first, last: last, birthday: birthday),
            nameKey: nameKey(first, last),
            existingFullKeys: existingFullKeys,
            existingNameKeys: existingNameKeys
        )
    }

    /// Writes the rows: each one updates the child it matches, adds a new
    /// child, or, when it can't be told apart from a child already in the
    /// class, is left out and named in `skippedDuplicates`.
    ///
    /// A row matches by name and birthday (the local day). Without that, it
    /// falls back to the name alone only when exactly one child already in
    /// the class has that name and no birthday is in the way: the row has
    /// none, or she has none (and the row's fills it in). A stored birthday
    /// is never overwritten, and two children already in the class with the
    /// same name are never treated as one.
    static func commit(
        parsed: Parsed,
        into context: NSManagedObjectContext,
        existingStudents: [CDStudent]
    ) throws -> Summary {
        var inserted = 0
        var updated = 0
        var skipped: [String] = []
        var index = MatchIndex(existing: existingStudents)

        for r in parsed.rows {
            switch index.match(for: r) {
            case .existing(let existing):
                if apply(r, to: existing) { updated += 1 }
            case .possibleDuplicate:
                skipped.append("\(r.firstName) \(r.lastName)")
            case .new:
                let student = CDStudent(context: context)
                student.firstName = r.firstName
                student.lastName = r.lastName
                student.birthday = r.birthday
                student.level = r.level ?? .lower
                student.dateStarted = r.dateStarted
                inserted += 1
                // Later rows in the file can merge into this child.
                index.add(student)
            }
        }
        try context.save()
        return Summary(
            totalRows: parsed.totalRows,
            insertedCount: inserted,
            updatedCount: updated,
            potentialDuplicates: parsed.potentialDuplicates,
            warnings: parsed.warnings,
            skippedDuplicates: skipped
        )
    }

    // MARK: - Helpers

    static func duplicateKey(for student: CDStudent) -> String {
        duplicateKey(first: student.firstName, last: student.lastName, birthday: student.birthday)
    }

    /// Name plus birthday, the birthday as its local calendar day: keyed by
    /// the GMT day, a birthday typed in after about 8 pm Eastern read as the
    /// next day, so a re-import missed her and added her again.
    static func duplicateKey(first: String, last: String, birthday: Date?) -> String {
        let name = nameKey(first, last)
        if let b = birthday {
            let day = AppCalendar.shared.dateComponents([.year, .month, .day], from: b)
            return name + "|" + String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        }
        return name
    }

    static func nameKey(_ first: String, _ last: String) -> String {
        "\(first) \(last)".normalizedNameKey()
    }

    static func parseLevel(from string: String) -> CDStudent.Level? {
        let s = string.normalizedForComparison()
        switch s {
        case "lower", "l", "lower elementary", "lower el", "lower elem":
            return .lower
        case "upper", "u", "upper elementary", "upper el", "upper elem":
            return .upper
        case "adolescent", "adol", "adolescence", "12-15", "erdkinder":
            return .adolescent
        default:
            return nil
        }
    }
}
