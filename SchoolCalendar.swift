import Foundation
import SwiftData

struct SchoolCalendar {
    private static var cal: Calendar { Calendar.current }

    private static func isWeekend(_ date: Date) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7 // 1=Sun, 7=Sat
    }

    static func isNonSchoolDay(_ date: Date, using context: ModelContext) -> Bool {
        let day = cal.startOfDay(for: date)
        if isWeekend(day) {
            // Weekend is non-school by default unless there's an override marking it as a school day
            let overrideDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = (try? context.fetch(overrideDescriptor)) ?? []
            return overrides.isEmpty
        } else {
            // Weekday: non-school only if explicitly marked
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let items: [NonSchoolDay] = (try? context.fetch(nsDescriptor)) ?? []
            return !items.isEmpty
        }
    }

    static func nonSchoolDays(in range: Range<Date>, using context: ModelContext) -> Set<Date> {
        var result: Set<Date> = []
        var d = cal.startOfDay(for: range.lowerBound)
        while d < range.upperBound {
            if isNonSchoolDay(d, using: context) {
                result.insert(d)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result
    }

    /// Toggle the "non-school" state for a date from the user's perspective.
    /// - For weekdays: toggles a NonSchoolDay record.
    /// - For weekends: toggles a SchoolDayOverride (weekend defaults to non-school; override makes it a school day).
    /// - Returns: The new non-school state after toggling.
    @discardableResult
    static func toggleNonSchoolDay(_ date: Date, using context: ModelContext) throws -> Bool {
        let day = cal.startOfDay(for: date)
        if isWeekend(day) {
            let overrideDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = try context.fetch(overrideDescriptor)
            if let existing = overrides.first {
                // Remove override -> weekend becomes non-school again
                context.delete(existing)
                try context.save()
                return true
            } else {
                // Add override -> weekend becomes a school day (non-school = false)
                context.insert(SchoolDayOverride(date: day))
                try context.save()
                return false
            }
        } else {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let items: [NonSchoolDay] = try context.fetch(nsDescriptor)
            if let existing = items.first {
                // Remove explicit non-school -> becomes school day
                context.delete(existing)
                try context.save()
                return false
            } else {
                // Add explicit non-school for weekday
                context.insert(NonSchoolDay(date: day))
                try context.save()
                return true
            }
        }
    }
}

