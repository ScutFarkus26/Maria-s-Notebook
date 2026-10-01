import Foundation
import CoreData

// The rules the attendance grid runs on, apart from its state. Most are the
// notebook's too and live in `AttendanceRules`; these forward to them so the
// grid and its tests read them off the model. Days off are this app's alone.
extension AssistantAttendanceViewModel {

    /// A child marked in after days away, for "Welcome back, Maya".
    struct Welcome: Equatable {
        let id = UUID()
        let name: String
    }

    /// The children still unmarked, by the names on their tiles: Close
    /// Arrival's list.
    var unmarkedNames: [String] {
        rows.filter { $0.status == .unmarked }.map(\.shortName)
    }

    /// Whether the bar offers Close Arrival (someone still unmarked) or shows
    /// Late. Never on a locked day or a day ahead.
    var showsArrivalControl: Bool {
        guard canMark, !isFuture else { return false }
        switch phase {
        case .arrival: return !unmarkedNames.isEmpty
        case .late: return true
        }
    }

    static func statusAfterTap(from status: AttendanceStatus, in phase: Phase) -> AttendanceStatus? {
        AttendanceRules.statusAfterTap(from: status, in: phase)
    }

    /// Present, late and left early all mean the child came in.
    static func isHere(_ status: AttendanceStatus) -> Bool {
        status == .present || status == .tardy || status == .leftEarly
    }

    static func allows(_ status: AttendanceStatus, on day: Date, now: Date = Date()) -> Bool {
        AttendanceRules.allows(status, on: day, now: now)
    }

    static func markerName(
        for row: Row,
        myRecordName: String?,
        myName: String?,
        guideName: String?
    ) -> String? {
        AttendanceRules.markerName(for: row, myRecordName: myRecordName, myName: myName, guideName: guideName)
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

    static func hereLine(_ rows: [Row]) -> String { AttendanceRules.hereLine(rows) }

    static func detailLine(_ rows: [Row]) -> String? { AttendanceRules.detailLine(rows) }

    /// The line in the bar once everyone's marked: "Everyone's here · 8:14"
    /// (the time only today; "for day 100" on that day), or "All marked · 20
    /// here, 2 home".
    static func completionText(
        _ rows: [Row],
        at time: Date?,
        milestone: AttendanceSchoolDayCount.Milestone? = nil
    ) -> String {
        AttendanceRules.completionText(rows, at: time, everyone: milestone?.everyoneHere ?? "Everyone's here")
    }
}
