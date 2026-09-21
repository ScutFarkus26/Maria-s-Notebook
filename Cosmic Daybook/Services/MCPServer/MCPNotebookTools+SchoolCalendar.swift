//
//  MCPNotebookTools+SchoolCalendar.swift
//  Cosmic Daybook
//
//  The school calendar over MCP: which days school is in session, and the
//  school-year settings behind it.
//
//  Days are written through `SchoolCalendarService.setSchoolDay`, the explicit
//  form of the settings grid's tap, so the same `NonSchoolDay` /
//  `SchoolDayOverride` rows land and every school-day cache in the app drops.
//  The year settings go through `SchoolYearStore` on `AppDependencies`, the
//  object the Settings pickers bind to, so a change here re-buckets the app
//  exactly as a change in Settings would.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Read

    static func schoolCalendarTool(
        context: @escaping MCPContextProvider,
        dependencies: @escaping MCPDependenciesProvider
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "school_calendar",
            title: "School Calendar",
            description: "The school-year settings (start date, day-counter epoch) and every "
                + "no-school weekday and weekend school day on the calendar. Defaults to the "
                + "current school year; pass from/to for another window, or date to ask about "
                + "one day.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "One day to ask about, YYYY-MM-DD"
                    ],
                    "from": [
                        "type": "string",
                        "description": .string("First day of the window, YYYY-MM-DD (default: start of "
                            + "the current school year)")
                    ],
                    "to": [
                        "type": "string",
                        "description": .string("Last day of the window, YYYY-MM-DD, inclusive (default: "
                            + "end of the current school year)")
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let settings = SchoolYearSettings.current(dependencies())
                if let day = try dayArgument(arguments, "date") {
                    return describeSchoolDay(AppCalendar.startOfDay(day), in: modelContext)
                }
                let window = try calendarWindow(arguments, settings: settings)
                return describeSchoolCalendar(settings: settings, window: window, in: modelContext)
            }
        )
    }

    /// The year settings as the read and the receipt print them. Read from the
    /// app's store when it is registered, else from the same defaults the store
    /// would load, so the read works before startup and under tests.
    struct SchoolYearSettings {
        let startMonth: Int
        let startDay: Int
        let counterEpoch: Date?

        static func current(_ dependencies: AppDependencies?) -> SchoolYearSettings {
            if let store = dependencies?.schoolYearStore {
                return SchoolYearSettings(store: store)
            }
            let defaults = UserDefaults.standard
            let month = defaults.object(forKey: UserDefaultsKeys.schoolYearStartMonth) as? Int
            let day = defaults.object(forKey: UserDefaultsKeys.schoolYearStartDay) as? Int
            return SchoolYearSettings(
                startMonth: month.flatMap { (1...12).contains($0) ? $0 : nil } ?? 9,
                startDay: day.flatMap { (1...31).contains($0) ? $0 : nil } ?? 1,
                counterEpoch: SchoolYearCounters.epoch
            )
        }

        var currentYear: SchoolYear {
            SchoolYear.containing(
                Date(), startMonth: startMonth, startDay: startDay, calendar: AppCalendar.shared
            )
        }

        var startText: String {
            let symbols = DateFormatter().monthSymbols ?? []
            let month = (1...symbols.count).contains(startMonth) ? symbols[startMonth - 1] : "\(startMonth)"
            return "\(month) \(startDay)"
        }

        var lines: [String] {
            let year = currentYear
            let lastDay = AppCalendar.shared.date(byAdding: .day, value: -1, to: year.end) ?? year.end
            var lines = [
                "School year starts \(startText). The current school year is \(year.label) "
                    + "(\(MCPNotebookTools.dayString(year.start)) to \(MCPNotebookTools.dayString(lastDay)))."
            ]
            if let epoch = counterEpoch {
                lines.append("Day counters start over on \(MCPNotebookTools.dayString(epoch)).")
            } else {
                lines.append("Day counters run over all history.")
            }
            return lines
        }
    }

    private static func calendarWindow(
        _ arguments: [String: JSONValue], settings: SchoolYearSettings
    ) throws -> ClosedRange<Date> {
        let year = settings.currentYear
        let from = try dayArgument(arguments, "from").map(AppCalendar.startOfDay) ?? year.start
        let defaultTo = AppCalendar.shared.date(byAdding: .day, value: -1, to: year.end) ?? year.end
        let to = try dayArgument(arguments, "to").map(AppCalendar.startOfDay) ?? defaultTo
        guard from <= to else {
            throw MCPToolError("from must be on or before to.")
        }
        return from...to
    }

    private static func describeSchoolDay(_ day: Date, in modelContext: NSManagedObjectContext) -> String {
        let label = "\(dayString(day)) (\(weekdayName(day)))"
        let isNonSchool = SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext)
        guard isNonSchool else {
            let weekend = isWeekend(day)
            return weekend
                ? "\(label) is a school day — a weekend marked as one."
                : "\(label) is a school day."
        }
        if let reason = nonEmpty(nonSchoolDayRows(in: day...day, modelContext).first?.reason) {
            return "\(label) is a no-school day — \(reason)."
        }
        return isWeekend(day)
            ? "\(label) is a weekend, so school is out."
            : "\(label) is a no-school day."
    }

    private static func describeSchoolCalendar(
        settings: SchoolYearSettings, window: ClosedRange<Date>,
        in modelContext: NSManagedObjectContext
    ) -> String {
        var sections: [String] = [settings.lines.joined(separator: "\n")]

        let closed = nonSchoolDayRows(in: window, modelContext)
            .filter { $0.date.map { !isWeekend($0) } ?? false }
        let windowText = "\(dayString(window.lowerBound)) to \(dayString(window.upperBound))"
        if closed.isEmpty {
            sections.append("No weekdays are marked no-school from \(windowText).")
        } else {
            let runs = collapseRuns(closed)
            var lines = ["No-school weekdays from \(windowText) (\(closed.count)):"]
            lines.append(contentsOf: runs.map(describeRun))
            sections.append(lines.joined(separator: "\n"))
        }

        let open = schoolDayOverrideRows(in: window, modelContext)
        if !open.isEmpty {
            var lines = ["Weekends marked as school days (\(open.count)):"]
            lines.append(contentsOf: open.map { "- \(dayString($0.date)) (\(weekdayName($0.date ?? .distantPast)))" })
            sections.append(lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Consecutive no-school weekdays with the same reason, so a break reads as
    /// one line rather than ten. Weekends inside a run do not break it.
    private struct NonSchoolRun {
        let first: Date
        var last: Date
        var count: Int
        let reason: String?

        /// True when `day` is the next weekday after this run and shares its reason.
        func continues(on day: Date, reason: String?) -> Bool {
            guard self.reason == reason else { return false }
            let next: Date = MCPNotebookTools.nextWeekday(after: last)
            return next == day
        }
    }

    private static func collapseRuns(_ rows: [CDNonSchoolDay]) -> [NonSchoolRun] {
        var runs: [NonSchoolRun] = []
        for row in rows {
            guard let day: Date = row.date else { continue }
            let reason: String? = nonEmpty(row.reason)
            let lastIndex: Int = runs.count - 1
            if lastIndex >= 0, runs[lastIndex].continues(on: day, reason: reason) {
                runs[lastIndex].last = day
                runs[lastIndex].count += 1
            } else {
                runs.append(NonSchoolRun(first: day, last: day, count: 1, reason: reason))
            }
        }
        return runs
    }

    private static func describeRun(_ run: NonSchoolRun) -> String {
        let reason = run.reason.map { " — \($0)" } ?? ""
        if run.count == 1 {
            return "- \(dayString(run.first)) (\(weekdayName(run.first)))\(reason)"
        }
        return "- \(dayString(run.first)) (\(weekdayName(run.first))) to "
            + "\(dayString(run.last)) (\(weekdayName(run.last))), \(run.count) weekdays\(reason)"
    }

    private static func nonSchoolDayRows(
        in window: ClosedRange<Date>, _ modelContext: NSManagedObjectContext
    ) -> [CDNonSchoolDay] {
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = rangePredicate(window)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return modelContext.safeFetch(request)
    }

    private static func schoolDayOverrideRows(
        in window: ClosedRange<Date>, _ modelContext: NSManagedObjectContext
    ) -> [CDSchoolDayOverride] {
        let request = CDFetchRequest(CDSchoolDayOverride.self)
        request.predicate = rangePredicate(window)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return modelContext.safeFetch(request)
    }

    private static func rangePredicate(_ window: ClosedRange<Date>) -> NSPredicate {
        let end = AppCalendar.dayRange(for: window.upperBound).end
        return NSPredicate(
            format: "date >= %@ AND date < %@", window.lowerBound as NSDate, end as NSDate
        )
    }

    /// The next Monday-to-Friday date strictly after `day`, ignoring the
    /// calendar's records — tells whether two no-school weekdays are
    /// consecutive across a weekend.
    static func nextWeekday(after day: Date) -> Date {
        var cursor = day
        for _ in 0..<7 {
            cursor = AppCalendar.shared.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            if !isWeekend(cursor) { return cursor }
        }
        return cursor
    }

    static func isWeekend(_ day: Date) -> Bool {
        let weekday = AppCalendar.shared.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }
}

extension MCPNotebookTools.SchoolYearSettings {
    /// The settings read straight off a store, for the receipt of a change.
    init(store: SchoolYearStore) {
        self.init(startMonth: store.startMonth, startDay: store.startDay, counterEpoch: store.counterEpoch)
    }
}
