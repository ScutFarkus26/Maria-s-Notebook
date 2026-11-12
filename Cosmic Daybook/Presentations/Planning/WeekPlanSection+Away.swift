// WeekPlanSection+Away.swift
// Who is away with a co-teacher on each day of the strip (docs/Plans/Plan -
// Co-teacher times when scheduling.md, Phase 3): loaded once for the whole
// window with `AwayTimes.days`, one timetable fetch and one school-calendar
// fetch, and handed to each day column, so no card or column fetches.
//
// It follows the window (`days`), so a day the strip grows into as it scrolls
// gets its away times too, and it reloads when the Schedules page, MCP or
// another device changes a group, a lane or a one-day change. It doesn't ride
// on `refreshCheckIns`, which returns early when the Show menu hides work.
//
// Split from the view for SwiftLint's type-length limit; the state these read
// is declared in WeekPlanSection.swift.

import CoreData
import SwiftUI

extension WeekPlanSection {

    /// What the away times are built from: a save touching one reloads them.
    nonisolated static let awayEntityNames: Set<String> = ["TimetableLane", "TimetableBlock", "TimetableChange"]

    /// How long a burst of timetable saves is waited out, as the Schedules
    /// page waits (`SchedulesPageModel.scheduleReload`).
    static let awayReloadWait = Duration.milliseconds(300)

    /// The window's days and the timetable's change count: a new key reloads.
    struct AwayKey: Equatable {
        let first: Date?
        let last: Date?
        let version: Int
    }

    var awayKey: AwayKey {
        AwayKey(first: days.first, last: days.last, version: awayVersion)
    }

    /// The away times of every day in `days` (school days, in order), keyed
    /// by start of day in `calendar`.
    static func awayDays(
        for days: [Date],
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) -> [Date: AwayDay] {
        guard let first = days.first, let last = days.last else { return [:] }
        return AwayTimes.days(from: first, through: last, in: context, calendar: calendar)
    }

    /// One day column's away times.
    func awayDay(for day: Date) -> AwayDay {
        awayDays[calendar.startOfDay(for: day)] ?? .empty
    }

    /// Reloads the away times for `key`. A timetable change waits out the
    /// rest of its burst first; a new window loads at once.
    func refreshAwayDays(_ key: AwayKey) async {
        if key.version != loadedAwayVersion {
            do { try await Task.sleep(for: Self.awayReloadWait) } catch { return }
        }
        awayDays = Self.awayDays(for: days, in: viewContext, calendar: calendar)
        loadedAwayVersion = key.version
    }

    /// Reloads on the window changing and on any timetable change while the
    /// strip is on screen (a hidden one catches up once on its return).
    func attachAwayRefresh<Content: View>(to content: Content) -> some View {
        content
            .task(id: awayKey) { await refreshAwayDays(awayKey) }
            .onPresentationDataChangeWhenVisible(of: Self.awayEntityNames, in: viewContext) {
                awayVersion &+= 1
            }
    }
}
