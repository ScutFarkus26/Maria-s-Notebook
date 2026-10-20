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
    /// Late. Never on a locked day or a day ahead. Reopened while the day
    /// still reads as closed (Close Arrival's absences, or the children it
    /// took in not all undone), it's offered with nobody unmarked too, as
    /// the way back to Late.
    var showsArrivalControl: Bool {
        guard canMark, !isFuture else { return false }
        switch phase {
        case .arrival: return !unmarkedNames.isEmpty || readsClosed
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

    /// Whether marking `status` brings a child in, for "Welcome back": present
    /// or late. Left Early counts as here, but isn't coming in (bug hunt
    /// 2026-10-17 review, At #7).
    static func comesIn(_ status: AttendanceStatus) -> Bool {
        status == .present || status == .tardy
    }

    static func allows(_ status: AttendanceStatus, on day: Date, now: Date = Date()) -> Bool {
        AttendanceRules.allows(status, on: day, now: now)
    }

    static func markerName(
        for row: Row,
        myRecordName: String?,
        myName: String?,
        guideName: String?,
        names: ClassroomNames.Snapshot = ClassroomNames.Snapshot()
    ) -> String? {
        AttendanceRules.markerName(
            for: row, myRecordName: myRecordName, myName: myName, guideName: guideName, viewerRole: .assistant,
            names: names
        )
    }

    /// Why `date` has no school, if it hasn't: a day off in the guide's
    /// calendar (with its reason), else a weekend that isn't a school
    /// Saturday, by the school-day rule (`SchoolDayChecker`). Any day off or
    /// school Saturday dated within `date` counts: one stored at another time
    /// than midnight (an older build, another time zone) read as a weekend
    /// here. Only the classroom share's (`AttendanceEmailLog.scopeToClassroom`):
    /// a notebook of her own on the same Apple Account keeps its days off in
    /// the private store, and they closed the class's school days on her
    /// phone (bug hunt 2026-10-20, #6). A stack with one store reads it all.
    static func dayOff(on date: Date, in context: NSManagedObjectContext) -> DayOff? {
        let day = AppCalendar.startOfDay(date)
        func dayRows<T: NSManagedObject>(_ type: T.Type) -> [T] {
            let request = CDFetchRequest(type)
            request.predicate = NSPredicate(
                format: "date >= %@ AND date < %@", day as NSDate, AppCalendar.addingDays(1, to: day) as NSDate
            )
            AttendanceEmailLog.scopeToClassroom(request, in: context)
            return context.safeFetch(request)
        }
        let holidays = dayRows(CDNonSchoolDay.self)
        let isDayOff = SchoolDayChecker.isNonSchoolDay(
            day,
            nonSchoolDayDates: holidays.isEmpty ? [] : [day],
            overrideDates: dayRows(CDSchoolDayOverride.self).isEmpty ? [] : [day]
        )
        guard isDayOff else { return nil }
        if let holiday = holidays.first {
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
