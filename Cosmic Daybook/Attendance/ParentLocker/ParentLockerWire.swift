import Foundation

// What ParentLocker's attendance page sends and takes (read 2026-10-12 from
// the teacher page, `/sis/newattendance.php`): the course list carried in the
// page's script, a class's roster, and a save's reply. The site has no public
// API, so these follow what its own page's script reads and writes, and every
// field is read leniently: an id may come as a number or a string, a flag as a
// bool, a number or "1". Compiled into the notebook and the Daybook Assistant.

// MARK: - Raw JSON

/// Any JSON value, kept as it came, so an attendance object the roster sent
/// can go back in a save with every field we don't know about untouched (the
/// page's own `save()` does the same). Integers stay integers.
nonisolated enum ParentLockerJSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ParentLockerJSON])
    case object([String: ParentLockerJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ParentLockerJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ParentLockerJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> ParentLockerJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    var objectValue: [String: ParentLockerJSON]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    var arrayValue: [ParentLockerJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    /// The value as text: a string as is, a whole number without a decimal
    /// point. Nil for null, objects and arrays.
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value):
            return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null, .array, .object: return nil
        }
    }

    /// The value as a whole number, from a number or a numeric string.
    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return value.rounded() == value ? Int(exactly: value) : nil
        case .string(let value): return Int(value.trimmingCharacters(in: .whitespaces))
        case .bool, .null, .array, .object: return nil
        }
    }

    /// Whether the value reads as yes: true, a non-zero number, or "1",
    /// "true" or "yes". Null and anything else read as no.
    var isTruthy: Bool {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .double(let value): return value != 0
        case .string(let value): return ["1", "true", "yes", "y", "t"].contains(value.lowercased())
        case .null, .array, .object: return false
        }
    }

    /// Text that says something: a non-empty string, or a number. Null,
    /// empty strings, false and "0" (the site's "no id") read as nil.
    var nonEmptyID: String? {
        guard let text = stringValue?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty, text != "0", text != "false", text != "null" else { return nil }
        return text
    }
}

// MARK: - Errors

/// What can go wrong talking to ParentLocker. Each says in plain words what
/// happened; the site's own text, a status code or a host go only to the log
/// and `details`.
nonisolated enum ParentLockerError: Error, Equatable, Sendable, LocalizedError {
    /// The site answered with its sign-in page (or sent us there): the saved
    /// cookies no longer work.
    case signedOut
    /// The attendance page no longer looks the way the app reads it.
    case pageChanged
    /// The site tried to send the request to another host; it was refused,
    /// so nothing (cookies included) went there.
    case redirectedOffSite(host: String)
    /// No answer, or one that wasn't the site's (offline, timed out, a 5xx).
    case unreachable
    /// The site answered the request with an error of its own.
    case refused(message: String)

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "ParentLocker signed you out. Sign in again to send attendance."
        case .pageChanged, .redirectedOffSite:
            "ParentLocker's attendance page changed, so the app can't send. " +
                "Take attendance on the ParentLocker site for now."
        case .unreachable:
            "Couldn't reach ParentLocker. It'll try again."
        case .refused:
            "ParentLocker didn't take the attendance. Check it on the ParentLocker site."
        }
    }

    /// What a Details disclosure or the log may show: the site's own text or
    /// the host. Never sign-in details.
    var details: String? {
        switch self {
        case .redirectedOffSite(let host): "Redirected to \(host)"
        case .refused(let message): message
        case .signedOut, .pageChanged, .unreachable: nil
        }
    }
}

// MARK: - Courses

/// One of the teacher's classes, from the page's `var courses = [...]` (and
/// `var additional_courses`).
nonisolated struct ParentLockerCourse: Sendable, Hashable, Decodable {
    let courseID: Int
    let name: String
    let period: Int
    /// What a save names the class's day by, as text.
    let attendanceReportID: String
    /// The same, exactly as the page gave it (`.null` when it gave none), so
    /// a save sends it back unchanged (`ParentLockerHTTP.reportID(for:)`).
    let attendanceReport: ParentLockerJSON
    /// `submitted`, `not_expected`, or empty when not taken.
    let reportStatus: String
    /// The class's mark is the child's mark for the day.
    let isDailyAttendance: Bool
    let hasAttendance: Bool

    init(
        courseID: Int, name: String, period: Int, attendanceReportID: String,
        reportStatus: String = "", isDailyAttendance: Bool = true, hasAttendance: Bool = true
    ) {
        self.courseID = courseID
        self.name = name
        self.period = period
        self.attendanceReportID = attendanceReportID
        attendanceReport = .string(attendanceReportID)
        self.reportStatus = reportStatus
        self.isDailyAttendance = isDailyAttendance
        self.hasAttendance = hasAttendance
    }

    init?(json: ParentLockerJSON) {
        guard let courseID = json["course_id"]?.intValue else { return nil }
        self.courseID = courseID
        name = json["course_name"]?.stringValue ?? ""
        period = json["period"]?.intValue ?? 0
        attendanceReport = json["attendance_report_id"] ?? .null
        attendanceReportID = attendanceReport.stringValue ?? ""
        reportStatus = json["attendance_report_status"]?.stringValue ?? ""
        isDailyAttendance = json["isDailyAttendance"]?.isTruthy ?? false
        hasAttendance = json["hasAttendance"]?.isTruthy ?? false
    }

    init(from decoder: Decoder) throws {
        let json = try ParentLockerJSON(from: decoder)
        guard let course = ParentLockerCourse(json: json) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No course_id"))
        }
        self = course
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(courseID)
        hasher.combine(period)
        hasher.combine(attendanceReportID)
    }

    /// The courses in the page's HTML: `var courses = [...];` and `var
    /// additional_courses = [...];`, each on one line, without repeats (by
    /// course and period). Nil when the page has no course list at all.
    static func courses(inPage html: String) -> [ParentLockerCourse]? {
        var found: [ParentLockerCourse] = []
        var sawList = false
        for name in ["courses", "additional_courses"] {
            guard let list = scriptArray(named: name, in: html) else { continue }
            sawList = true
            for course in list
            where !found.contains(where: { $0.courseID == course.courseID && $0.period == course.period }) {
                found.append(course)
            }
        }
        return sawList ? found : nil
    }

    /// The JSON array a `var <name> = [...];` line of the page carries.
    private static func scriptArray(named name: String, in html: String) -> [ParentLockerCourse]? {
        let marker = "var \(name)"
        for line in html.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker) else { continue }
            let rest = trimmed.dropFirst(marker.count).drop { $0 == " " || $0 == "\t" }
            guard rest.first == "=",
                  let open = rest.firstIndex(of: "["),
                  let close = rest.lastIndex(of: "]"), open < close else { continue }
            let data = Data(rest[open...close].utf8)
            guard let items = (try? JSONDecoder().decode(ParentLockerJSON.self, from: data))?.arrayValue else {
                continue
            }
            return items.compactMap(ParentLockerCourse.init(json:))
        }
        return nil
    }
}

// MARK: - Marks

/// The three kinds of mark the app sends, by the `type` the school's marks
/// carry. A mark's id belongs to the school (689/690/691 at this one), so a
/// mark is always looked up by its type.
nonisolated enum ParentLockerMarkType: String, Sendable, CaseIterable {
    case present
    case late
    case absent
}

/// One of the school's marks (`attendance_settings`).
nonisolated struct ParentLockerMark: Sendable, Equatable, Decodable {
    let id: String
    let name: String
    let type: String
    let isExcused: Bool
    let isHidden: Bool
    let isDeleted: Bool
    let listOrder: Int

    init(id: String, name: String, type: String, isExcused: Bool = false,
         isHidden: Bool = false, isDeleted: Bool = false, listOrder: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.isExcused = isExcused
        self.isHidden = isHidden
        self.isDeleted = isDeleted
        self.listOrder = listOrder
    }

    init?(json: ParentLockerJSON) {
        guard let id = json["id"]?.nonEmptyID else { return nil }
        self.id = id
        name = json["name"]?.stringValue ?? ""
        type = (json["type"]?.stringValue ?? "").lowercased()
        isExcused = json["is_excused"]?.isTruthy ?? false
        isHidden = json["is_hidden"]?.isTruthy ?? false
        isDeleted = json["deleted_at"]?.nonEmptyID != nil
        listOrder = json["list_order"]?.intValue ?? 0
    }

    init(from decoder: Decoder) throws {
        let json = try ParentLockerJSON(from: decoder)
        guard let mark = ParentLockerMark(json: json) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No mark id"))
        }
        self = mark
    }

    /// The `attendance_code` a save sends: the page's own shape, every field a string.
    var attendanceCode: ParentLockerJSON {
        .object([
            "id": .string(id),
            "type": .string(type),
            "name": .string(name),
            "is_excused": .string(isExcused ? "1" : "0")
        ])
    }

    /// The school's mark of `type`: one still in use (not deleted), a shown
    /// one before a hidden one, then by list order. Nil when the school has none.
    static func find(_ type: ParentLockerMarkType, in marks: [ParentLockerMark]) -> ParentLockerMark? {
        marks.filter { $0.type == type.rawValue && !$0.isDeleted }
            .min { ($0.isHidden ? 1 : 0, $0.listOrder) < ($1.isHidden ? 1 : 0, $1.listOrder) }
    }
}
