import Foundation
import CoreData

/// The guide's front-desk attendance email settings, carried to the assistants:
/// the recipients, the report format, and the time the front desk needs it by.
///
/// The guide sets them in Settings › Communication › Attendance Email, where
/// they are also kept as iCloud key-value settings (`AttendanceEmailPrefs`).
/// The notebook copies them into this one row in the classroom share (schema
/// 12), and both apps write the email from the row, so the guide's devices
/// and the assistants' phones send the same email to the same people
/// (domain-logic review A5). Only the lead guide writes it; the newest row wins.
/// Read and write it through `AttendanceEmailLog`, never directly.
@objc(CDAttendanceEmailSettings)
nonisolated public class CDAttendanceEmailSettings: NSManagedObject {
    @NSManaged public var id: UUID?
    /// Whether the guide has the attendance email turned on.
    @NSManaged public var isEnabled: Bool
    /// The recipients as the guide typed them: commas or semicolons between.
    @NSManaged public var toAddresses: String?
    /// `AttendanceEmailNameOrder` raw value.
    @NSManaged public var nameOrderRaw: String?
    @NSManaged public var groupByLevel: Bool
    /// When the front desk needs it by, in minutes after midnight (9:00 = 540).
    @NSManaged public var deadlineMinutes: Int32
    @NSManaged public var modifiedAt: Date?
    /// How the day's attendance goes to the school: `AttendanceSendMethod` raw
    /// value, "email" or "parentLocker" (schema 18). A row written before then
    /// reads as email.
    @NSManaged public var sendMethodRaw: String
    /// The school's ParentLocker host ("yyli.parentlocker.com"); nil reads as
    /// `AttendanceEmailLog.defaultParentLockerSite` (schema 18).
    @NSManaged public var parentLockerSite: String?
    /// The classroom's time zone, a `TimeZone` identifier ("America/New_York")
    /// that every device's day math follows (schema 25). Nil, or an identifier
    /// `TimeZone(identifier:)` doesn't know, reads as the device's own zone.
    @NSManaged public var classroomTimeZoneID: String?
    /// The school session's first and last days (schema 25): days outside them
    /// are days off for every reader. Nil keeps the behavior from before them.
    @NSManaged public var sessionFirstDay: Date?
    @NSManaged public var sessionLastDay: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceEmailSettings", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.isEnabled = true
        self.deadlineMinutes = Int32(AttendanceEmailLog.defaultDeadlineMinutes)
        self.modifiedAt = Date()
    }
}

nonisolated extension CDAttendanceEmailSettings: Identifiable {}

// MARK: - The classroom's calendar (schema 25)

/// The classroom's time zone and school session on the settings row: read by
/// `ClassroomCalendarFollower` and `SchoolSession.read`, written from
/// Settings › School Year. Compiled into both apps; only the lead guide's
/// devices write.
extension AttendanceEmailLog {

    /// The zone a first real save from a Mac gives a row with none: the
    /// Mac's own, where sharing is set up and the class's days were made.
    /// Other devices never fill it in by themselves; a phone may be traveling.
    nonisolated static var firstSaveZoneID: String? {
        #if os(macOS)
        TimeZone.current.identifier
        #else
        nil
        #endif
    }

    /// The classroom's time zone and session as the share carries them: each
    /// from the newest row that holds one, so a duplicate row written by
    /// another of the guide's devices can't hide them.
    static func classroomCalendar(in context: NSManagedObjectContext) -> ClassroomCalendar.Snapshot {
        let rows = settingsRows(in: context)
        return ClassroomCalendar.Snapshot(
            timeZoneID: rows.lazy.compactMap(\.classroomTimeZoneID).first,
            session: rows.lazy
                .compactMap { SchoolSession(firstDay: $0.sessionFirstDay, lastDay: $0.sessionLastDay) }
                .first
        )
    }

    /// Writes the classroom's time zone and session onto the newest settings
    /// row; with none yet, onto a new row holding `base` (this device's
    /// attendance settings). A session is both days or neither. Only the lead
    /// guide may. `modifiedAt` stays as it is: it orders the attendance
    /// settings (the newest row wins), and the launch's stand-in row must not
    /// come to outrank the guide's own because a session was set on it.
    /// Returns whether anything changed; the caller saves.
    @discardableResult
    static func saveClassroomCalendar(
        timeZoneID: String?,
        session: SchoolSession?,
        base: @autoclosure () -> Settings,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard role == .leadGuide else { return false }
        let current = classroomCalendar(in: context)
        guard current.timeZoneID != timeZoneID || current.session != session else { return false }
        if settingsRows(in: context).isEmpty {
            saveSettings(base(), role: role, now: launchSeedStamp, in: context)
        }
        guard let row = settingsRows(in: context).first else { return false }
        row.classroomTimeZoneID = timeZoneID
        row.sessionFirstDay = session?.firstDay
        row.sessionLastDay = session?.lastDay
        ClassroomCalendarFollower.refresh(from: context)
        return true
    }

    /// Every settings row, newest first: one, or two while two of the
    /// guide's devices have each written one.
    static func settingsRows(in context: NSManagedObjectContext) -> [CDAttendanceEmailSettings] {
        let request = CDFetchRequest(CDAttendanceEmailSettings.self)
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        scopeToClassroom(request, in: context)
        return context.safeFetch(request)
    }

    /// The days with no school in `range`, by `SchoolDayChecker`'s rule, from
    /// the days off and school-day overrides the classroom share holds: what
    /// the reminders go by (the front desk's and the Assistant's arrival
    /// reminder). In the Assistant, the guide's calendar only, never a
    /// notebook of the assistant's own on the same Apple Account, as for the
    /// settings and sends above (bug hunt 2026-10-20). The notebook reads both
    /// stores, as `SchoolDayChecker.nonSchoolDaySet` does.
    static func nonSchoolDays(
        in range: Range<Date>,
        using context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Set<Date> {
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        guard start < end else { return [] }
        let daysOff = classroomDates(CDNonSchoolDay.self, from: start, to: end, in: context, calendar: calendar)
        let overrides = classroomDates(CDSchoolDayOverride.self, from: start, to: end, in: context, calendar: calendar)
        // Days the school session is out on are days off too (review R20).
        let session = SchoolSession.read(in: context)
        var result: Set<Date> = []
        var day = start
        while day < end {
            let isOff = SchoolDayChecker.isNonSchoolDay(
                day, nonSchoolDayDates: daysOff, overrideDates: overrides, session: session, calendar: calendar
            )
            if isOff { result.insert(day) }
            let next = AppCalendar.dayStart(after: day, calendar: calendar)
            guard next > day else { break }
            day = next
        }
        return result
    }

    /// The start of each day in [`start`, `end`) holding a record of `type`
    /// in the classroom's store.
    private static func classroomDates<T: NSManagedObject>(
        _ type: T.Type, from start: Date, to end: Date, in context: NSManagedObjectContext, calendar: Calendar
    ) -> Set<Date> {
        let request = CDFetchRequest(T.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        scopeToClassroom(request, in: context)
        return Set(context.safeFetch(request).compactMap { record in
            (record.value(forKey: "date") as? Date).map { calendar.startOfDay(for: $0) }
        })
    }

    /// Hands the zone and session of rows about to be dropped to `kept`,
    /// where it has none of its own.
    static func carryClassroomCalendar(
        from dropped: some Sequence<CDAttendanceEmailSettings>, to kept: CDAttendanceEmailSettings
    ) {
        for row in dropped {
            if kept.classroomTimeZoneID == nil { kept.classroomTimeZoneID = row.classroomTimeZoneID }
            if kept.sessionFirstDay == nil || kept.sessionLastDay == nil,
               let first = row.sessionFirstDay, let last = row.sessionLastDay {
                kept.sessionFirstDay = first
                kept.sessionLastDay = last
            }
        }
    }
}
