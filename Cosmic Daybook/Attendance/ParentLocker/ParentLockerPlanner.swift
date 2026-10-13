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
///   arrived late) with "Left early at 1:30 PM". Unmarked sends nothing, and the Notes box is
///   written only when there is something to say, or to clear what the app
///   wrote there for an earlier mark (never anyone else's words).
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
            let note = mark.leftAt.map { "Left early at \(timeText($0))" } ?? "Left early"
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

    /// Whether a Notes box holds exactly what the app writes there: a
    /// reason's word ("Sick") or a left-early line ("Left early at 1:30 PM").
    /// Only such text is cleared when the mark changes to one with nothing to
    /// say; anyone else's words in the box are left as they are.
    static func isAppNote(_ comment: String) -> Bool {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Left early") || reasonWords.contains(text)
    }

    /// Every reason's word (a test keeps it in step with `AbsenceReason.given`).
    private static let reasonWords = Set(
        [AbsenceReason.sick, .vacation, .appointment, .family, .other].compactMap(reasonText)
    )

    /// "1:30 PM", in this device's time zone and locale.
    static func defaultTimeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
    /// `only` (nil: all of them) are compared and sent.
    static func plan(
        children: [Child],
        marks: [UUID: DayMark],
        rosters: [ParentLockerRoster],
        only: Set<UUID>? = nil,
        day: Date,
        calendar: Calendar = AppCalendar.shared,
        timeText: (Date) -> String = defaultTimeText
    ) -> Plan {
        var builder = PlanBuilder()
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
                return compare(student, childID: childID, wanted: wanted, marks: roster.marks, into: &builder)
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
        marks: [ParentLockerMark],
        into builder: inout PlanBuilder
    ) -> Entry? {
        switch wanted {
        case .unknown:
            builder.skip(childID, .unknownMark)
        case .nothing:
            let holdsMark = student.isConfirmed && student.currentMarkID != nil
            builder.skip(childID, holdsMark ? .cantClear(currentMark: student.currentMarkName) : .unmarked)
        case .send(let type, let wantedComment):
            guard let mark = ParentLockerMark.find(type, in: marks) else {
                builder.skip(childID, .noSuchMark(type))
                return nil
            }
            // Nothing to say, but the box still holds what the app wrote for
            // an earlier mark ("Sick" before Late, "Left early at…" before
            // Back in Class): it's cleared, so the office doesn't read it.
            let comment = wantedComment ?? (isAppNote(student.comment) ? "" : nil)
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

    /// What `plan` gathers as it goes.
    private struct PlanBuilder {
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
