import Foundation

/// Works out what to send to ParentLocker, without touching the network or
/// the store: which ParentLocker child each notebook child is, what mark each
/// should carry, and, against the rosters just loaded, which children differ.
/// The result is one save per class plus the children it left alone and why.
///
/// The rules (plan "ParentLocker attendance", Marks and matching):
/// - Here goes as Present, Late as Late, Absent as Absent with only the reason
///   picked in the Notes box (Close Arrival's automatic absence with none, so
///   the office's note stays), and Left Early as Present (Late when the child
///   arrived late) with "Left early at 1:30 PM". Unmarked sends nothing. The
///   app writes its note only into an empty box or over its own earlier note,
///   and clears only its own: a parent's or the office's words always stay
///   (bug hunt 2026-11-05, #10). Its own is what this device wrote for the
///   child, or its "Left early at 1:30 PM" line, never words that only look
///   like its own (review of the fixes, W3).
/// - A child is matched by the stored `parentLockerID`, else by name, and a
///   name match counts only when exactly one child fits on both sides. A
///   stored "Not matched" (`notMatchedID`) is never matched or sent, and a
///   ParentLocker child two of ours claim is sent for neither.
/// - ParentLocker children who aren't matched, and classes holding none of
///   the notebook's children, are never touched. Neither are rows the office
///   locked, and a mark can't be cleared, only changed.
/// Compiled into the notebook and the Daybook Assistant.
nonisolated enum ParentLockerPlanner {

    // MARK: - Inputs

    /// A notebook child, as the planner needs them.
    struct Child: Sendable, Equatable {
        let id: UUID
        let firstName: String
        let lastName: String
        let nickname: String?
        /// The stored match (`CDStudent.parentLockerID`), if any.
        let parentLockerID: String?

        init(id: UUID, firstName: String, lastName: String, nickname: String? = nil, parentLockerID: String? = nil) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.nickname = nickname
            self.parentLockerID = parentLockerID
        }
    }

    /// A child's mark for the day, read from the record that wins among the
    /// day's duplicates (`AttendanceDeduplication`), as raw values.
    struct DayMark: Sendable, Equatable {
        let statusRaw: String
        let absenceReasonRaw: String
        let leftAt: Date?
        let statusBeforeLeavingRaw: String?

        init(statusRaw: String, absenceReasonRaw: String = AbsenceReason.none.rawValue,
             leftAt: Date? = nil, statusBeforeLeavingRaw: String? = nil) {
            self.statusRaw = statusRaw
            self.absenceReasonRaw = absenceReasonRaw
            self.leftAt = leftAt
            self.statusBeforeLeavingRaw = statusBeforeLeavingRaw
        }
    }

    // MARK: - Mark mapping

    /// What a child's day asks ParentLocker to hold.
    enum Wanted: Sendable, Equatable {
        /// Unmarked: nothing to send.
        case nothing
        /// A mark a newer build added; this build doesn't know how to send it.
        case unknown
        /// This mark, with this Notes box text (nil leaves the box as it is).
        case send(ParentLockerMarkType, comment: String?)
    }

    /// The mark to send for `mark`. `timeText` writes a time for the Notes box
    /// ("1:30 PM").
    static func wanted(for mark: DayMark?, timeText: (Date) -> String = defaultTimeText) -> Wanted {
        guard let mark, !mark.statusRaw.isEmpty, mark.statusRaw != AttendanceStatus.unmarked.rawValue else {
            return .nothing
        }
        switch AttendanceStatus(rawValue: mark.statusRaw) {
        case .present:
            return .send(.present, comment: nil)
        case .tardy:
            return .send(.late, comment: nil)
        case .absent:
            // Close Arrival's automatic absence reads as no reason: the office's
            // or a parent's words in the box stay (bug hunt 2026-10-13
            // afternoon, M6), and only the app's own are cleared (`isAppNote`).
            return .send(.absent, comment: reasonText(AbsenceReason(rawValue: mark.absenceReasonRaw) ?? .none))
        case .leftEarly:
            let arrivedLate = mark.statusBeforeLeavingRaw == AttendanceStatus.tardy.rawValue
            let note = mark.leftAt.map { leftEarlyAt + timeText($0) } ?? leftEarly
            return .send(arrivedLate ? .late : .present, comment: note)
        case .unmarked:
            return .nothing
        case nil:
            return .unknown
        }
    }

    /// The reason as the Notes box says it: the word the guide picked, the
    /// same as `AbsenceReason.displayName`. Nil for no reason.
    static func reasonText(_ reason: AbsenceReason) -> String? {
        switch reason {
        case .none: nil
        case .sick: "Sick"
        case .vacation: "Vacation"
        case .appointment: "Appointment"
        case .family: "Family"
        case .other: "Other"
        }
    }

    /// Whether a Notes box holds the app's own note: what this device wrote
    /// there for the child today (`wrote`), or, with no record, the one form
    /// nobody else writes, "Left early at " and a time. Words alone don't
    /// say whose they are: a "Sick" a parent or the office typed is theirs
    /// (review of the 2026-11-05 fixes, W3). Only the app's own note is
    /// replaced or cleared; anyone else's words in the box ("Left early for
    /// the dentist") are left as they are (bug hunt 2026-11-05, #10).
    static func isAppNote(_ comment: String, wrote: Set<String> = []) -> Bool {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if wrote.contains(text) { return true }
        guard text.hasPrefix(leftEarlyAt) else { return false }
        let time = text.dropFirst(leftEarlyAt.count)
        return time.range(of: appTimePattern, options: .regularExpression) != nil
    }

    /// The times the app has written (W4): "1:30 PM" with AM or PM in any
    /// case, "a.m." or "p.m.", after a plain space or the system's narrow
    /// one, or a two-digit 24-hour "13:30" or "09:15". A bare "2:15" is
    /// someone else's.
    private static let appTimePattern =
        #"^(?:(?:0?[1-9]|1[0-2]):[0-5][0-9][ \x{202F}](?i:am|pm|a\.m\.|p\.m\.)|(?:[01][0-9]|2[0-3]):[0-5][0-9])$"#

    /// What goes in the Notes box: `wanted` (the app's note, nil for nothing
    /// to say) over `current` (the box as ParentLocker holds it), `wrote`
    /// being what this device wrote there for the child today. The app's
    /// note goes only into an empty box or over the app's own earlier note;
    /// with nothing to say, only the app's own note is cleared. Nil leaves the
    /// box as it is.
    static func noteToWrite(_ wanted: String?, over current: String, wrote: Set<String> = []) -> String? {
        let ours = isAppNote(current, wrote: wrote)
        if let wanted {
            let empty = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return empty || ours ? wanted : nil
        }
        return ours ? "" : nil
    }

    private static let leftEarly = "Left early"
    private static let leftEarlyAt = "Left early at "

    /// "1:30 PM", in this device's time zone, always in this form with a
    /// plain space whatever the device's language or clock, so the app can
    /// tell its own note later (bug hunt 2026-11-05, #25).
    static func defaultTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// The day as ParentLocker writes it: `YYYY-M-D`, no leading zeros.
    static func dateText(_ day: Date, calendar: Calendar = AppCalendar.shared) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: - Outputs

    /// One child's change within a class's save.
    struct Entry: Sendable, Equatable {
        let childID: UUID
        let studentID: String
        let type: ParentLockerMarkType
        /// The Notes box written, nil when left as it was.
        let comment: String?
        /// The roster's attendance object with the change made: what the save sends.
        let attendance: ParentLockerJSON
    }

    /// One class's save.
    struct Batch: Sendable, Equatable {
        let course: ParentLockerCourse
        let attendanceReportID: String
        /// `YYYY-M-D`.
        let date: String
        let entries: [Entry]

        /// The save's `students`: the attendance objects, in order.
        var students: [ParentLockerJSON] { entries.map(\.attendance) }
    }

    /// Why the plan leaves a child alone.
    enum SkipReason: Sendable, Equatable {
        /// No ParentLocker child fits (or the stored one isn't on the rosters).
        case unmatched
        /// The guide picked "Not matched": left out on purpose, said nowhere.
        case leftOut
        /// More than one ParentLocker child fits, or one fits more than one of ours.
        case ambiguous(studentIDs: [String])
        /// Unmarked here and in ParentLocker: nothing to do.
        case unmarked
        /// A mark this build doesn't know.
        case unknownMark
        /// Unmarked here but ParentLocker holds a mark, which it can't clear.
        case cantClear(currentMark: String?)
        /// The office locked the row on another mark.
        case locked(currentMark: String?)
        /// The school has no mark of this type: its page changed.
        case noSuchMark(ParentLockerMarkType)
        /// The roster has no attendance row for the child (null or empty):
        /// a save would carry no ids (bug hunt 2026-11-05, #12).
        case noAttendanceRow
    }

    /// A child the plan leaves alone, and why.
    struct Skip: Sendable, Equatable {
        let childID: UUID
        let reason: SkipReason
    }

    struct Plan: Sendable, Equatable {
        /// One save per class that has something to change.
        let batches: [Batch]
        let skipped: [Skip]
        /// Children ParentLocker already holds as we would send them.
        let upToDate: Set<UUID>
        /// Matches found by name this time: the guide's devices store them as
        /// `parentLockerID`.
        let newMatches: [UUID: String]

        var isEmpty: Bool { batches.isEmpty }
    }

    // MARK: - Planning

    /// Compares `children`'s marks with the rosters and plans the saves.
    /// Matching always looks at every child given; only the children in
    /// `only` (nil: all of them) are compared and sent. `ownNotes`: the notes
    /// this device wrote in each child's Notes box today, by `course_id`,
    /// which alone it may replace or clear (`noteToWrite`).
    static func plan(
        children: [Child],
        marks: [UUID: DayMark],
        rosters: [ParentLockerRoster],
        only: Set<UUID>? = nil,
        day: Date,
        calendar: Calendar = AppCalendar.shared,
        ownNotes: [UUID: [Int: Set<String>]] = [:],
        timeText: (Date) -> String = defaultTimeText
    ) -> Plan {
        var builder = PlanBuilder(ownNotes: ownNotes)
        let matches = match(children: children, rosters: rosters)
        // Matching gives a ParentLocker child to one notebook child at most;
        // should two ever claim one, neither is sent.
        let unique = childByStudentID(matches)
        var childByStudentID: [String: UUID] = [:]
        for child in children where only?.contains(child.id) ?? true {
            switch matches[child.id] ?? .unmatched {
            case .matched(let studentID, _) where unique[studentID] != child.id:
                builder.skip(child.id, .ambiguous(studentIDs: [studentID]))
            case .matched(let studentID, let byName):
                childByStudentID[studentID] = child.id
                if byName { builder.newMatches[child.id] = studentID }
            case .unmatched:
                builder.skip(child.id, .unmatched)
            case .leftOut:
                builder.skip(child.id, .leftOut)
            case .ambiguous(let ids):
                builder.skip(child.id, .ambiguous(studentIDs: ids))
            }
        }

        let dateText = dateText(day, calendar: calendar)
        for roster in rosters {
            let entries = roster.students.compactMap { student -> Entry? in
                guard let childID = childByStudentID[student.studentID] else { return nil }
                let wanted = wanted(for: marks[childID], timeText: timeText)
                return compare(student, childID: childID, wanted: wanted, in: roster, into: &builder)
            }
            guard !entries.isEmpty else { continue }
            builder.batches.append(Batch(
                course: roster.course,
                attendanceReportID: roster.attendanceReportID ?? roster.course.attendanceReportID,
                date: dateText,
                entries: entries
            ))
        }
        return Plan(
            batches: builder.batches, skipped: builder.skipped,
            upToDate: builder.upToDate, newMatches: builder.newMatches
        )
    }

    /// One matched child against their roster row: the change to send, or
    /// nil with the child noted as up to date or skipped.
    private static func compare(
        _ student: ParentLockerRosterStudent,
        childID: UUID,
        wanted: Wanted,
        in roster: ParentLockerRoster,
        into builder: inout PlanBuilder
    ) -> Entry? {
        switch wanted {
        case .unknown:
            builder.skip(childID, .unknownMark)
        case .nothing:
            let holdsMark = student.isConfirmed && student.currentMarkID != nil
            builder.skip(childID, holdsMark ? .cantClear(currentMark: student.currentMarkName) : .unmarked)
        case .send(let type, let wantedComment):
            guard student.hasAttendanceRow else {
                builder.skip(childID, .noAttendanceRow)
                return nil
            }
            guard let mark = ParentLockerMark.find(type, in: roster.marks) else {
                builder.skip(childID, .noSuchMark(type))
                return nil
            }
            // The app's note goes into an empty box or over its own earlier
            // one; with nothing to say, its own earlier note ("Sick" before
            // Late) is cleared. Anyone else's words stay (`noteToWrite`).
            let wrote = builder.ownNotes[childID]?[roster.course.courseID] ?? []
            let comment = noteToWrite(wantedComment, over: student.comment, wrote: wrote)
            let sameMark = student.isConfirmed && student.currentMarkID == mark.id
            if student.isLocked {
                if sameMark {
                    builder.upToDate.insert(childID)
                } else {
                    builder.skip(childID, .locked(currentMark: student.currentMarkName))
                }
            } else if sameMark, comment == nil || comment == student.comment {
                builder.upToDate.insert(childID)
            } else {
                return Entry(
                    childID: childID, studentID: student.studentID, type: type, comment: comment,
                    attendance: student.attendanceToSave(mark: mark, comment: comment)
                )
            }
        }
        return nil
    }

    /// What `plan` gathers as it goes, and the notes it may replace (`plan`'s `ownNotes`).
    private struct PlanBuilder {
        let ownNotes: [UUID: [Int: Set<String>]]
        var batches: [Batch] = []
        var skipped: [Skip] = []
        var upToDate: Set<UUID> = []
        var newMatches: [UUID: String] = [:]

        /// Notes a skip once, though a child on two classes' rosters is seen twice.
        mutating func skip(_ childID: UUID, _ reason: SkipReason) {
            let item = Skip(childID: childID, reason: reason)
            if !skipped.contains(item) { skipped.append(item) }
        }
    }
}
