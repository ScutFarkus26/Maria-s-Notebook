import Foundation
import CoreData

// The rules the attendance grid runs on, apart from its state: what a tap
// means, what a day allows, who marked a child, days off, and the tallies.
// Pure, so the tests call them directly. What Siri needs too lives outside
// the view model: the tiles' names (`AssistantDayRoll.gridNames`) and the
// remembered Late phase (`AssistantLatePhase`).
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

    /// The line in the bar once everyone's marked: "Everyone's here · 8:14"
    /// (the time only today), or "All marked · 20 here, 2 home".
    static func completionText(_ rows: [Row], at time: Date?) -> String {
        let here = rows.count { [.present, .tardy, .leftEarly].contains($0.status) }
        let home = rows.count { $0.status == .absent }
        guard home > 0 else {
            return time.map { "Everyone's here · \(AssistantClock.string($0))" } ?? "Everyone's here"
        }
        return "All marked · \(here) here, \(home) home"
    }
}
