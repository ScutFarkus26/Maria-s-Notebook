import Foundation
import CoreData

/// Children coming back after being away: absent on each of the last three
/// (or more) school days before the day on screen. Their tile waves, so she
/// knows to welcome them at the door, and waves again when she marks them in.
///
/// Only marked absences count. A school day with no record for the child (the
/// roll wasn't taken, or they weren't in the class yet) ends the run, so a
/// week without attendance never makes the whole class "back".
enum AssistantWelcomeBack {
    /// Away this many school days in a row before a welcome.
    static let threshold = 3
    /// How far back to count; a child away longer shows as "15 or more".
    static let lookback = AttendanceRules.welcomeBackLookback
    /// Calendar days searched for `lookback` school days, with room for a
    /// two-week break.
    private static let window = 40

    /// School days away in a row, from `statuses` ordered newest first (nil
    /// for a day with no record).
    static func daysAway(statuses: [AttendanceStatus?]) -> Int {
        var count = 0
        for status in statuses {
            guard status == .absent else { break }
            count += 1
        }
        return count
    }

    /// The children back on `date` after `threshold` or more school days
    /// away: student ID (its uuidString, as records keep it) to days away.
    static func returning(
        on date: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [String: Int] {
        let day = calendar.startOfDay(for: date)
        guard let windowStart = calendar.date(byAdding: .day, value: -window, to: day) else { return [:] }
        let daysOff = SchoolDayChecker.nonSchoolDaySet(in: windowStart..<day, using: context, calendar: calendar)

        // The school days before `date`, newest first.
        var schoolDays: [Date] = []
        var cursor = day
        while schoolDays.count < lookback,
              let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
              previous >= windowStart {
            cursor = previous
            if !daysOff.contains(previous) { schoolDays.append(previous) }
        }
        guard schoolDays.count >= threshold, let oldest = schoolDays.last else { return [:] }

        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", oldest as NSDate, day as NSDate)
        var statuses: [String: [Date: AttendanceStatus]] = [:]
        for record in context.safeFetch(request).deduplicatedPerStudentDay() {
            guard let recordDate = record.date else { continue }
            statuses[record.studentID, default: [:]][calendar.startOfDay(for: recordDate)] = record.status
        }

        var result: [String: Int] = [:]
        for (student, byDay) in statuses {
            let away = daysAway(statuses: schoolDays.map { byDay[$0] })
            if away >= threshold { result[student] = away }
        }
        return result
    }

    /// "Back after 4 days", "Back after 15+ days".
    static func phrase(daysAway: Int) -> String {
        AttendanceRules.welcomeBackPhrase(daysAway: daysAway)
    }
}
