// HebrewParshaService.swift
// Canonical parsha keys, display names, and current-parsha computation.
//
// The parsha-of-week algorithm uses the standard diaspora reading cycle driven by
// Hebrew-year type (weekday of Rosh Hashanah + leap-year flag + year length). It maps
// a Shabbat to a parsha via the classic "Four Gates" year-type schedules. For V1 this
// covers 14 diaspora schedules; Israel scheduling is deferred.

import Foundation

enum HebrewParshaService {

    /// One Shabbat in a Hebrew year: its Gregorian date, the parsha key read that
    /// week (`nil` when a festival displaces the weekly reading), and the name of
    /// the displacing festival (`nil` on a normal week).
    struct ShabbatEntry {
        let date: Date
        let parshaKey: String?
        let festivalName: String?
    }

    // MARK: - Canonical Keys (annual-cycle order)

    static let allParshaKeys: [String] = [
        "bereishit", "noach", "lech-lecha", "vayera", "chayei-sarah", "toldot",
        "vayetzei", "vayishlach", "vayeshev", "miketz", "vayigash", "vayechi",
        "shemot", "vaera", "bo", "beshalach", "yitro", "mishpatim",
        "terumah", "tetzaveh", "ki-tisa", "vayakhel", "pekudei",
        "vayikra", "tzav", "shemini", "tazria", "metzora", "acharei-mot", "kedoshim", "emor", "behar", "bechukotai",
        "bamidbar", "naso", "behaalotecha", "shelach", "korach", "chukat", "balak", "pinchas", "matot", "masei",
        "devarim", "vaetchanan", "eikev", "reeh", "shoftim", "ki-teitzei", "ki-tavo", "nitzavim", "vayelech",
        "haazinu", "vzot-haberachah"
    ]

    // MARK: - Shabbat of Week

    /// Returns the start-of-day Saturday for the week containing `date`. If `date` is
    /// already a Saturday, returns that same day.
    static func shabbatOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        // weekday: 1 = Sunday ... 7 = Saturday
        let daysUntilSaturday = (7 - weekday) % 7
        let shabbat: Date
        if daysUntilSaturday == 0 {
            shabbat = date
        } else {
            shabbat = calendar.date(byAdding: .day, value: daysUntilSaturday, to: date) ?? date
        }
        return calendar.startOfDay(for: shabbat)
    }

    // MARK: - Current Parsha (diaspora)

    /// Computes the canonical parsha key read on the Shabbat of the week containing `on`.
    /// Uses the diaspora reading schedule. Returns `nil` if the Hebrew year falls outside
    /// the coded year-type lookup (which covers all Gregorian years reachable via
    /// `Calendar(identifier: .hebrew)`).
    static func currentParshaKey(on date: Date = Date()) -> String? {
        let shabbat = shabbatOfWeek(containing: date, calendar: gregorian)
        return parshaKey(forShabbat: shabbat)
    }

    /// Returns every Shabbat in the Hebrew year containing `date`, paired with its parsha
    /// key (nil on festival-displaced Shabbatot) and the festival name (when displaced).
    /// Walks from the first sedra Shabbat after Simchat Torah through next Rosh Hashanah.
    static func shabbatotForHebrewYear(containing date: Date) -> [ShabbatEntry] {
        guard let hebYear = hebrew.dateComponents([.year], from: date).year else { return [] }
        // Find the cycle year whose Simchat Torah is on or before `date`.
        let candidateCycleYears: [Int] = [hebYear, hebYear - 1]
        for cycleYear in candidateCycleYears {
            guard let simchatTorah = simchatTorahDate(
                hebYear: cycleYear, hebrew: hebrew, gregorian: gregorian
            ) else {
                continue
            }
            guard date >= simchatTorah else { continue }

            // Memoized per cycle year: `ParshaCalendarView` reads this from a computed
            // property, so SwiftUI re-ran the whole year walk on every body pass.
            // Checked only after the cycle year is confirmed, so a cached year is never
            // returned for a date that belongs to the previous cycle.
            if let cached = yearShabbatotCache[cycleYear] { return cached }

            // First Shabbat after Simchat Torah carries the first sedra reading (Bereishit).
            var current = shabbatOfWeek(containing: simchatTorah, calendar: gregorian)
            if gregorian.isDate(simchatTorah, inSameDayAs: current) {
                current = gregorian.date(byAdding: .day, value: 7, to: current) ?? current
            } else if current < simchatTorah {
                current = gregorian.date(byAdding: .day, value: 7, to: current) ?? current
            }

            var nextRHComps = DateComponents()
            nextRHComps.year = cycleYear + 1
            nextRHComps.month = 1
            nextRHComps.day = 1
            guard let nextRH = hebrew.date(from: nextRHComps).map(gregorian.startOfDay) else {
                return []
            }

            var results: [ShabbatEntry] = []
            while current < nextRH {
                let key = parshaKey(forShabbat: current)
                let festival = displacingFestivalName(forShabbat: current)
                results.append(ShabbatEntry(date: current, parshaKey: key, festivalName: festival))
                guard let next = gregorian.date(byAdding: .day, value: 7, to: current) else { break }
                current = next
            }
            yearShabbatotCache[cycleYear] = results
            return results
        }
        return []
    }

    /// Returns the diaspora festival that displaces the weekly parsha on this Shabbat,
    /// or `nil` if a normal weekly reading takes place. The three displacing windows are
    /// Sukkot/Shemini Atzeret, Pesach (including Chol HaMoed Shabbatot), and Shavuot.
    static func displacingFestivalName(forShabbat shabbat: Date) -> String? {
        let comps = hebrew.dateComponents([.month, .day], from: shabbat)
        guard let month = comps.month, let day = comps.day else { return nil }
        if month == 1, (15...22).contains(day) { return "Sukkot" }
        if month == 8, (15...22).contains(day) { return "Pesach" }
        if month == 10, day == 6 || day == 7 { return "Shavuot" }
        return nil
    }

    /// Returns the parsha key read on the given Shabbat (start-of-day Saturday, Gregorian).
    /// Returns `nil` when the Shabbat is displaced by a festival reading.
    static func parshaKey(forShabbat shabbat: Date) -> String? {
        if displacingFestivalName(forShabbat: shabbat) != nil { return nil }

        // Determine the Hebrew year of the *next* Rosh Hashanah on or before `shabbat`,
        // so the cycle reference anchor is correct for dates before Simchat Torah too.
        guard let hebYear = hebrew.dateComponents([.year], from: shabbat).year else {
            return nil
        }

        // Find Simchat Torah (23 Tishri) for the Hebrew year enclosing `shabbat`.
        // If shabbat falls before Simchat Torah of hebYear, we are still in the cycle
        // that began at Simchat Torah of the PREVIOUS Hebrew year.
        let candidateCycleYears: [Int] = [hebYear, hebYear - 1]
        for cycleYear in candidateCycleYears {
            guard let simchatTorah = simchatTorahDate(hebYear: cycleYear, hebrew: hebrew, gregorian: gregorian),
                  shabbat >= simchatTorah else {
                continue
            }
            let firstShabbat = shabbatOfWeek(containing: simchatTorah, calendar: gregorian)
            // If Simchat Torah itself is a Shabbat we still advance to the NEXT Shabbat,
            // because Simchat Torah's Torah reading replaces the weekly parsha that day.
            let adjustedFirstShabbat: Date
            if gregorian.isDate(simchatTorah, inSameDayAs: firstShabbat) {
                adjustedFirstShabbat = gregorian.date(byAdding: .day, value: 7, to: firstShabbat) ?? firstShabbat
            } else {
                adjustedFirstShabbat = firstShabbat < simchatTorah
                    ? (gregorian.date(byAdding: .day, value: 7, to: firstShabbat) ?? firstShabbat)
                    : firstShabbat
            }

            let daysBetween = gregorian.dateComponents([.day], from: adjustedFirstShabbat, to: shabbat).day ?? 0
            guard daysBetween >= 0, daysBetween % 7 == 0 else { return nil }
            let weekIndex = daysBetween / 7

            // Use the year-type schedule to map weekIndex -> parsha key.
            if let schedule = sedraSchedule(hebYear: cycleYear, hebrew: hebrew, gregorian: gregorian),
               weekIndex >= 0, weekIndex < schedule.count {
                return schedule[weekIndex]
            }
            return nil
        }
        return nil
    }
}
