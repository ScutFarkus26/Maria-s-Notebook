import Foundation

// A class's roster and a save's reply, as ParentLocker's attendance page
// sends them (see ParentLockerWire.swift).

// MARK: - Roster

/// One child on a class's roster, with the attendance object the page would
/// save for them, kept whole.
nonisolated struct ParentLockerRosterStudent: Sendable, Equatable {
    let studentID: String
    let firstName: String
    let lastName: String
    let alternateName: String
    /// The roster's attendance object, exactly as sent.
    let attendance: ParentLockerJSON

    init?(json: ParentLockerJSON) {
        guard let id = json["student_id"]?.nonEmptyID else { return nil }
        studentID = id
        firstName = json["first_name"]?.stringValue ?? ""
        lastName = json["last_name"]?.stringValue ?? ""
        alternateName = json["alternate_name"]?.stringValue ?? ""
        attendance = json["attendance"] ?? .object([:])
    }

    /// The id of the mark ParentLocker holds now, nil when none.
    var currentMarkID: String? {
        attendance["attendance_code_id"]?.nonEmptyID ?? attendance["attendance_code"]?["id"]?.nonEmptyID
    }

    /// The name of the mark ParentLocker holds now, as its own code says.
    var currentMarkName: String? {
        attendance["attendance_code"]?["name"]?.stringValue
    }

    /// Whether the mark held is a saved one, not just the expected one the
    /// page shows before anyone takes attendance.
    var isConfirmed: Bool { attendance["confirmed"]?.isTruthy ?? false }

    /// The Notes box.
    var comment: String { attendance["comment"]?.stringValue ?? "" }

    /// The office set this mark ("Locked by Admin"); neither the page nor the app changes it.
    var isLocked: Bool { attendance["is_locked"]?.isTruthy ?? false }

    var lockedTitle: String? { attendance["is_locked_title"]?.stringValue }

    /// The attendance object to save: the roster's own, with only the mark,
    /// `confirmed` and (when given) the Notes box changed, as the page's `save()` does.
    func attendanceToSave(mark: ParentLockerMark, comment: String?) -> ParentLockerJSON {
        var fields = attendance.objectValue ?? [:]
        fields["attendance_code"] = mark.attendanceCode
        fields["confirmed"] = .bool(true)
        if let comment { fields["comment"] = .string(comment) }
        return .object(fields)
    }

    /// The row as this device saw it: the saved mark (none until someone
    /// takes attendance) and the Notes box.
    var seenRow: ParentLockerSeen.Row {
        ParentLockerSeen.Row(markID: isConfirmed ? currentMarkID : nil, comment: comment)
    }
}

/// What ParentLocker held for one child when this device last looked, per
/// class the child is on, from a roster it loaded or a save it made. An
/// imported change goes over ParentLocker's mark only while ParentLocker
/// still holds this: anything else means another device has saved the child
/// since, most likely the one that made the change, with a newer mark than
/// the one that synced in here (`ParentLockerPlanner.changedElsewhere`).
nonisolated struct ParentLockerSeen: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        /// The saved mark's id; nil when nobody has saved one.
        let markID: String?
        /// The Notes box.
        let comment: String
    }

    /// By the class's `course_id`.
    var rows: [Int: Row] = [:]

    /// Whether ParentLocker holds a saved mark for the child in any class.
    var holdsMark: Bool { rows.values.contains { $0.markID != nil } }
}

/// A class's roster for a day (`action: "course_roster"`).
nonisolated struct ParentLockerRoster: Sendable, Equatable {
    let course: ParentLockerCourse
    let students: [ParentLockerRosterStudent]
    let marks: [ParentLockerMark]
    let isToday: Bool
    let isDailyAttendance: Bool
    /// The reply's own report id, when it carries one; a save prefers it to the course's.
    let attendanceReportID: String?

    init(course: ParentLockerCourse, students: [ParentLockerRosterStudent], marks: [ParentLockerMark],
         isToday: Bool = true, isDailyAttendance: Bool = true, attendanceReportID: String? = nil) {
        self.course = course
        self.students = students
        self.marks = marks
        self.isToday = isToday
        self.isDailyAttendance = isDailyAttendance
        self.attendanceReportID = attendanceReportID
    }

    /// Reads a roster reply. Throws `.refused` when the reply carries an
    /// error, and `.pageChanged` when it has no students list.
    init(reply json: ParentLockerJSON, course: ParentLockerCourse) throws {
        if let message = ParentLockerRoster.errorText(json["error"]) {
            throw ParentLockerError.refused(message: message)
        }
        guard let students = json["students"]?.arrayValue else { throw ParentLockerError.pageChanged }
        self.course = course
        self.students = students.compactMap(ParentLockerRosterStudent.init(json:))
        marks = (json["attendance_settings"]?.arrayValue ?? []).compactMap(ParentLockerMark.init(json:))
        isToday = json["is_today"]?.isTruthy ?? false
        isDailyAttendance = json["isDailyAttendance"]?.isTruthy ?? course.isDailyAttendance
        attendanceReportID = json["attendance_report_id"]?.nonEmptyID
    }

    /// A reply's `error`: text that says something, or "error" for a bare
    /// true, a non-zero number, or a list or object with something in it.
    /// Nothing, false, zero and an empty list or object are no error.
    static func errorText(_ value: ParentLockerJSON?) -> String? {
        switch value {
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "0" || trimmed.lowercased() == "false" ? nil : trimmed
        case .bool(true): return "error"
        case .int(let number): return number == 0 ? nil : "error \(number)"
        case .double(let number): return number == 0 ? nil : "error"
        case .array(let items): return items.isEmpty ? nil : "error"
        case .object(let fields): return fields.isEmpty ? nil : "error"
        case .bool(false), .null, nil: return nil
        }
    }
}

// MARK: - Save reply

/// What a save answers (`action: "save"`).
nonisolated struct ParentLockerSaveReply: Sendable, Equatable {
    /// Someone changed a child since the roster was loaded: what we wanted,
    /// and what ParentLocker holds now.
    nonisolated struct Conflict: Sendable, Equatable {
        let studentID: String
        let desiredMarkID: String?
        let currentMarkID: String?

        init(studentID: String, desiredMarkID: String?, currentMarkID: String?) {
            self.studentID = studentID
            self.desiredMarkID = desiredMarkID
            self.currentMarkID = currentMarkID
        }

        init?(json: ParentLockerJSON) {
            guard let id = json["student_id"]?.nonEmptyID else { return nil }
            studentID = id
            desiredMarkID = json["desired"]?["attendance_code_id"]?.nonEmptyID
            currentMarkID = json["current"]?["attendance_code_id"]?.nonEmptyID
        }

        /// ParentLocker already holds what we wanted, so there is nothing to tell.
        var alreadyEqual: Bool { desiredMarkID == currentMarkID }
    }

    /// The site's `updated`, kept as sent.
    let updated: ParentLockerJSON?
    let conflicts: [Conflict]

    init(updated: ParentLockerJSON? = nil, conflicts: [Conflict] = []) {
        self.updated = updated
        self.conflicts = conflicts
    }

    /// Reads a save reply; throws `.refused` when it carries an error.
    init(reply json: ParentLockerJSON) throws {
        if let message = ParentLockerRoster.errorText(json["error"]) {
            throw ParentLockerError.refused(message: message)
        }
        updated = json["updated"]
        conflicts = (json["conflicts"]?.arrayValue ?? []).compactMap(Conflict.init(json:))
    }
}
