// SchoolYearStore.swift
// The observable "viewing year" lens. Holds the configurable start month/day and the active
// selection, persists both to UserDefaults, and resolves the selection to a `DateRange` that
// fetch sites scope against. Lives as a lazy service on `AppDependencies`; views read it via
// `@Environment(\.dependencies)`.

import Foundation
import SwiftUI

@Observable
@MainActor
final class SchoolYearStore {
    /// Number of school years in a cycle (Montessori three-year cycle).
    let cycleYears = 3

    /// Month the school year starts in (1–12). Default September.
    var startMonth: Int {
        didSet { UserDefaults.standard.set(startMonth, forKey: UserDefaultsKeys.schoolYearStartMonth) }
    }
    /// Day of month the school year starts on (1–31). Default 1.
    var startDay: Int {
        didSet { UserDefaults.standard.set(startDay, forKey: UserDefaultsKeys.schoolYearStartDay) }
    }
    /// The active viewing lens.
    var selection: SchoolYearSelection {
        didSet { UserDefaults.standard.set(Self.token(for: selection), forKey: UserDefaultsKeys.schoolYearSelection) }
    }

    private var calendar: Calendar { AppCalendar.shared }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        let month = defaults.object(forKey: UserDefaultsKeys.schoolYearStartMonth) as? Int
        let day = defaults.object(forKey: UserDefaultsKeys.schoolYearStartDay) as? Int
        let resolvedMonth = (month.map { (1...12).contains($0) ? $0 : 9 }) ?? 9
        let resolvedDay = (day.map { (1...31).contains($0) ? $0 : 1 }) ?? 1
        startMonth = resolvedMonth
        startDay = resolvedDay

        let cal = AppCalendar.shared
        let currentYear = SchoolYear.containing(Date(), startMonth: resolvedMonth, startDay: resolvedDay, calendar: cal)
        if let token = defaults.string(forKey: UserDefaultsKeys.schoolYearSelection),
           let restored = Self.selection(
               from: token, startMonth: resolvedMonth, startDay: resolvedDay, calendar: cal
           ) {
            selection = restored
        } else {
            selection = .year(currentYear)
        }
    }

    // MARK: - Derived

    /// The school year containing today.
    var current: SchoolYear {
        SchoolYear.containing(Date(), startMonth: startMonth, startDay: startDay, calendar: calendar)
    }

    /// The date range for the active selection, or nil for `.allTime` (no filtering).
    var activeRange: DateRange? { range(for: selection) }

    /// Resolves any selection to a date range (nil = no filter).
    func range(for selection: SchoolYearSelection) -> DateRange? {
        switch selection {
        case .allTime:
            return nil
        case .year(let year):
            return year.range
        case .cycle(let anchor):
            let firstBeginYear = anchor.beginYear - (cycleYears - 1)
            let first = SchoolYear.beginning(
                in: firstBeginYear, startMonth: startMonth, startDay: startDay, calendar: calendar
            )
            return DateRange(start: first.start, end: anchor.end)
        }
    }

    /// The school years offered in the picker: the current year and the prior five.
    /// TODO(phase-1): derive the lower bound from the earliest activity date in the store.
    var availableYears: [SchoolYear] {
        let begin = current.beginYear
        return (0...5).map { offset in
            SchoolYear.beginning(
                in: begin - offset, startMonth: startMonth, startDay: startDay, calendar: calendar
            )
        }
    }

    // MARK: - Selection helpers

    /// True when the lens is the single current school year (the "fresh" default).
    var isCurrentYearSelected: Bool {
        if case .year(let year) = selection { return year.beginYear == current.beginYear }
        return false
    }

    /// Compact label for the picker button.
    var menuButtonLabel: String {
        switch selection {
        case .year(let year): return year.label
        case .cycle: return "Cycle"
        case .allTime: return "All years"
        }
    }

    /// Banner text shown whenever the lens is *not* the current year.
    var bannerText: String {
        switch selection {
        case .year(let year): return "Viewing \(year.label)"
        case .cycle(let anchor):
            let firstBeginYear = anchor.beginYear - (cycleYears - 1)
            return "Viewing \(firstBeginYear)–\(anchor.beginYear + 1) cycle"
        case .allTime: return "Viewing all years"
        }
    }

    func selectCurrentYear() { selection = .year(current) }
    func selectCurrentCycle() { selection = .cycle(anchor: current) }
    func select(_ year: SchoolYear) { selection = .year(year) }
    func selectAllTime() { selection = .allTime }

    func isSelected(_ year: SchoolYear) -> Bool {
        if case .year(let selected) = selection { return selected.beginYear == year.beginYear }
        return false
    }

    var isCycleSelected: Bool {
        if case .cycle = selection { return true }
        return false
    }

    var isAllTimeSelected: Bool {
        if case .allTime = selection { return true }
        return false
    }

    // MARK: - Persistence tokens

    static func token(for selection: SchoolYearSelection) -> String {
        switch selection {
        case .allTime: return "all"
        case .year(let year): return "year:\(year.beginYear)"
        case .cycle(let anchor): return "cycle:\(anchor.beginYear)"
        }
    }

    static func selection(
        from token: String,
        startMonth: Int,
        startDay: Int,
        calendar: Calendar
    ) -> SchoolYearSelection? {
        if token == "all" { return .allTime }
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let beginYear = Int(parts[1]) else { return nil }
        let year = SchoolYear.beginning(
            in: beginYear, startMonth: startMonth, startDay: startDay, calendar: calendar
        )
        switch parts[0] {
        case "year": return .year(year)
        case "cycle": return .cycle(anchor: year)
        default: return nil
        }
    }
}
