import Foundation
import CoreData

/// Which school day of the year a day is ("Day 37"), and the two worth a
/// party: the first day, and the hundredth, which elementary classes make a
/// fuss of.
///
/// The Assistant can't read the guide's school-year setting (it lives on the
/// guide's devices only), so it works the start out from what they share: the first day since
/// July 1 that any child was marked here (present, late or left early). A
/// vacation marked absent ahead of time can't make a false first day. July,
/// not September: this class began on Aug 31. From there it counts school
/// days by the guide's calendar (`SchoolDayChecker`), the same days the ‹ ›
/// arrows step through.
enum AttendanceSchoolDayCount {

    enum Milestone: Equatable {
        case firstDay
        case hundredthDay

        /// In the header, in Today's place.
        var title: String {
            switch self {
            case .firstDay: return "First Day"
            case .hundredthDay: return "Day 100"
            }
        }

        /// The first half of "Everyone's here · 8:14" on this day.
        var everyoneHere: String {
            switch self {
            case .firstDay: return "Everyone's here for the first day"
            case .hundredthDay: return "Everyone's here for day 100"
            }
        }
    }

    static func milestone(for number: Int?) -> Milestone? {
        switch number {
        case 1: return .firstDay
        case 100: return .hundredthDay
        default: return nil
        }
    }

    #if DEBUG
    /// The sample class's `-AssistantSampleDayNumber`: a hundredth day in
    /// September needs a first day before July.
    static var yearStartOverride: Date?
    #endif

    /// July 1 on or before `date`: where a school year's first day is looked
    /// for.
    static func yearStart(for date: Date, calendar: Calendar = AppCalendar.shared) -> Date {
        #if DEBUG
        if let yearStartOverride { return yearStartOverride }
        #endif
        let year = calendar.component(.year, from: date)
        let startYear = calendar.component(.month, from: date) >= 7 ? year : year - 1
        return calendar.date(from: DateComponents(year: startYear, month: 7, day: 1)) ?? calendar.startOfDay(for: date)
    }

    /// The first day any child was marked here in the school year beginning
    /// `yearStart`, or nil before the first mark comes in.
    static func firstDay(
        inYearStarting yearStart: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Date? {
        guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else { return nil }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        let here = [AttendanceStatus.present, .tardy, .leftEarly].map(\.rawValue)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND statusRaw IN %@",
            yearStart as NSDate, yearEnd as NSDate, here
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.fetchLimit = 1
        return context.safeFetch(request).first?.date.map { calendar.startOfDay(for: $0) }
    }

    /// `date`'s school day number counting from `firstDay` as 1, or nil
    /// before the first day or on a day off. `nonSchoolDays` holds the days
    /// off from `firstDay` through `date`, as start-of-day dates.
    static func number(
        of date: Date,
        firstDay: Date,
        nonSchoolDays: Set<Date>,
        calendar: Calendar = AppCalendar.shared
    ) -> Int? {
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.startOfDay(for: firstDay)
        guard day >= cursor, !nonSchoolDays.contains(day) else { return nil }
        var count = 0
        while cursor <= day {
            if !nonSchoolDays.contains(cursor) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }

    /// `date`'s school day number, reading the calendar from the store.
    static func number(
        of date: Date,
        firstDay: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Int? {
        let day = calendar.startOfDay(for: date)
        guard day >= firstDay, let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let daysOff = SchoolDayChecker.nonSchoolDaySet(in: firstDay..<end, using: context, calendar: calendar)
        return number(of: day, firstDay: firstDay, nonSchoolDays: daysOff, calendar: calendar)
    }
}

/// Keeps the grid from recounting on every reload: it counts when the day
/// changes, while the count isn't known yet, or when the year's first day
/// has moved. Both apps count the same way, so the guide's notebook and her
/// assistant's phone always show the same day number.
///
/// The first day found is checked again on each reload (one small fetch):
/// the year's marks come down from iCloud in pieces on a first download, and
/// a first day found among the early pieces used to stand for good, leaving
/// the day number short until a relaunch.
struct AttendanceDayCounter {
    /// Each school year's first day, by its July 1.
    private var firstDays: [Date: Date] = [:]
    /// The day last counted.
    private var countedDay: Date?

    enum Outcome: Equatable {
        /// The number already shown still stands.
        case unchanged
        /// The day's number: nil on a day off or before the year's first day.
        case counted(Int?)
    }

    mutating func count(
        _ day: Date,
        isDayOff: Bool,
        current: Int?,
        in context: NSManagedObjectContext
    ) -> Outcome {
        let yearStart = AttendanceSchoolDayCount.yearStart(for: day)
        if !isDayOff, let known = firstDays[yearStart] {
            let found = AttendanceSchoolDayCount.firstDay(inYearStarting: yearStart, in: context)
            if found != known {
                firstDays[yearStart] = found
                countedDay = nil
            }
        }
        guard countedDay != day || (current == nil && !isDayOff) else { return .unchanged }
        countedDay = day
        guard !isDayOff else { return .counted(nil) }
        if firstDays[yearStart] == nil {
            firstDays[yearStart] = AttendanceSchoolDayCount.firstDay(inYearStarting: yearStart, in: context)
        }
        let number = firstDays[yearStart].flatMap {
            AttendanceSchoolDayCount.number(of: day, firstDay: $0, in: context)
        }
        return .counted(number)
    }
}
