import Foundation
import CoreData

// The rules the attendance grid runs on, apart from its state: what a tap
// means, what a day allows, the names on the phone grid, days off, and the
// remembered Late phase. Pure, so the tests (and the intents) call them
// directly.
extension AssistantAttendanceViewModel {

    /// What a tap on `row` does in the current phase. During Arrival a tap
    /// marks present and a second tap unmarks; during Late a tap turns absent
    /// (or unmarked) into tardy and a second tap turns it back. A present
    /// child is left alone during Late: the long-press menu changes that.
    static func statusAfterTap(from status: AttendanceStatus, in phase: Phase) -> AttendanceStatus? {
        switch (phase, status) {
        case (.arrival, .present): return .unmarked
        case (.arrival, _): return .present
        case (.late, .tardy): return .absent
        case (.late, .absent), (.late, .unmarked): return .tardy
        case (.late, _): return nil
        }
    }

    /// Whether `status` can be set on `day`. Ahead of the day there's no
    /// arrival to record, so only Absent, or clearing a mark, is allowed.
    /// The intents follow the same rule.
    static func allows(_ status: AttendanceStatus, on day: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        guard calendar.startOfDay(for: day) > calendar.startOfDay(for: now) else { return true }
        return status == .absent || status == .unmarked
    }

    /// Who made the mark on a tile: "you", another assistant's name, or "your
    /// guide" (the owner's name when CloudKit gives it; the guide's own marks
    /// carry no name). Nil while unmarked, and for old marks made before
    /// attribution existed.
    static func markerName(
        for row: Row,
        myRecordName: String?,
        myName: String?,
        guideName: String?
    ) -> String? {
        guard row.status != .unmarked else { return nil }
        switch row.recordedBy {
        case CDClassroomMembership.ClassroomRole.leadGuide.rawValue:
            return guideName ?? "your guide"
        case CDClassroomMembership.ClassroomRole.assistant.rawValue:
            if let id = row.recordedByID, let mine = myRecordName {
                return id == mine ? "you" : (row.recordedByName ?? "another assistant")
            } else if let name = row.recordedByName {
                return name == myName ? "you" : name
            }
            return "an assistant"
        default:
            return nil
        }
    }

    /// "Marked by you at 8:02": `markerName` with the mark's time.
    static func markedByLine(
        for row: Row,
        myRecordName: String?,
        myName: String?,
        guideName: String?
    ) -> String? {
        guard let who = markerName(for: row, myRecordName: myRecordName, myName: myName, guideName: guideName)
        else { return nil }
        let time = row.status == .leftEarly ? row.leftAt : row.markedAt
        let at = time.map { " at \(AssistantAttendanceTile.clock($0))" } ?? ""
        return "Marked by \(who)\(at)"
    }

    /// The fewest letters that still tell each child apart: the first name
    /// alone ("Ari"), the last initial only where a first name is shared
    /// ("Etty G", "Etty R"), and the full name where the initials clash too.
    /// Kept to this screen on purpose; everywhere else the notebook's short
    /// form is always "Maya S".
    static func gridNames(for students: [CDStudent]) -> [NSManagedObjectID: String] {
        func key(_ name: String) -> String { name.trimmed().lowercased() }
        let firstNameCounts = Dictionary(grouping: students) { key($0.firstName) }.mapValues(\.count)
        let shortNameCounts = Dictionary(grouping: students) { key($0.shortName) }.mapValues(\.count)
        var names: [NSManagedObjectID: String] = [:]
        for student in students {
            let first = student.firstName.trimmed()
            if !first.isEmpty, firstNameCounts[key(first)] == 1 {
                names[student.objectID] = first
            } else if shortNameCounts[key(student.shortName)] == 1 {
                names[student.objectID] = student.shortName
            } else {
                names[student.objectID] = student.fullName
            }
        }
        return names
    }

    /// Why `date` has no school, if it hasn't: a day off in the guide's
    /// calendar (with its reason), else a weekend.
    static func dayOff(on date: Date, in context: NSManagedObjectContext) -> DayOff? {
        guard SchoolDayChecker.isNonSchoolDay(date, using: context) else { return nil }
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(date) as NSDate)
        request.fetchLimit = 1
        if let holiday = context.safeFetchFirst(request) {
            let reason = holiday.reason?.trimmed() ?? ""
            return .holiday(reason.isEmpty ? nil : reason)
        }
        return .weekend
    }

    /// Remembers, on this device, which days were switched to Late, so the
    /// phase survives a relaunch mid-morning. Each day keeps its own: closing
    /// arrival on another day (or reopening it there) leaves today's alone, so
    /// a late child is still tardy after a look at yesterday.
    enum LatePhaseMemory {
        private static let key = "Assistant.latePhaseDays"
        /// Before each day kept its own, one day was remembered here.
        private static let singleDayKey = "Assistant.latePhaseDay"
        /// The most recent days kept; older ones are forgotten.
        static let dayLimit = 31

        static func isLate(on day: Date, defaults: UserDefaults = .standard) -> Bool {
            lateDays(defaults).contains { Calendar.current.isDate($0, inSameDayAs: day) }
        }

        static func setLate(_ late: Bool, on day: Date, defaults: UserDefaults = .standard) {
            var days = lateDays(defaults).filter { !Calendar.current.isDate($0, inSameDayAs: day) }
            if late { days.append(Calendar.current.startOfDay(for: day)) }
            days = Array(days.sorted().suffix(dayLimit))
            defaults.set(days, forKey: key)
            defaults.removeObject(forKey: singleDayKey)
        }

        static func forget(defaults: UserDefaults = .standard) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: singleDayKey)
        }

        private static func lateDays(_ defaults: UserDefaults) -> [Date] {
            var days = defaults.array(forKey: key) as? [Date] ?? []
            if let single = defaults.object(forKey: singleDayKey) as? Date { days.append(single) }
            return days
        }
    }

    /// "18 here · 2 absent · 1 late", leaving out what's zero.
    static func tally(_ rows: [Row]) -> String {
        let counts = Dictionary(grouping: rows, by: \.status).mapValues(\.count)
        let parts: [(AttendanceStatus, String)] = [
            (.present, "here"), (.tardy, "late"), (.absent, "absent"),
            (.leftEarly, "left early"), (.unmarked, "not marked")
        ]
        let text = parts.compactMap { status, word in
            counts[status].map { "\($0) \(word)" }
        }
        return text.joined(separator: " · ")
    }

    /// The tally when the full one won't fit beside the arrival button:
    /// late and left early count as here ("3 here · 1 absent · 18 not
    /// marked"), since the tiles already say which.
    static func shortTally(_ rows: [Row]) -> String {
        let here = rows.filter { [.present, .tardy, .leftEarly].contains($0.status) }.count
        let absent = rows.filter { $0.status == .absent }.count
        let unmarked = rows.filter { $0.status == .unmarked }.count
        let parts = [(here, "here"), (absent, "absent"), (unmarked, "not marked")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return parts.joined(separator: " · ")
    }

    /// Why there's no attendance on a day off, in words.
    static func dayOffText(_ dayOff: DayOff, isToday: Bool) -> String {
        switch dayOff {
        case .weekend:
            return isToday
                ? "It's the weekend. Attendance opens again on the next school day."
                : "That's a weekend. Use the arrows to move between school days."
        case .holiday(let reason?):
            return "\(reason). No attendance is taken on this day."
        case .holiday(nil):
            return "This is a day off on your guide's school calendar."
        }
    }
}
