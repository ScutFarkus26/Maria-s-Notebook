// HebrewParshaService.swift
// Canonical parsha keys, display names, and current-parsha computation.
//
// The parsha-of-week algorithm uses the standard diaspora reading cycle driven by
// Hebrew-year type (weekday of Rosh Hashanah + leap-year flag + year length). It maps
// a Shabbat to a parsha via the classic "Four Gates" year-type schedules. For V1 this
// covers 14 diaspora schedules; Israel scheduling is deferred.

import Foundation

enum HebrewParshaService {

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

    // MARK: - Display Names

    private static let displayNames: [String: String] = [
        "bereishit": "Bereishit",
        "noach": "Noach",
        "lech-lecha": "Lech-Lecha",
        "vayera": "Vayera",
        "chayei-sarah": "Chayei Sarah",
        "toldot": "Toldot",
        "vayetzei": "Vayetzei",
        "vayishlach": "Vayishlach",
        "vayeshev": "Vayeshev",
        "miketz": "Miketz",
        "vayigash": "Vayigash",
        "vayechi": "Vayechi",
        "shemot": "Shemot",
        "vaera": "Vaera",
        "bo": "Bo",
        "beshalach": "Beshalach",
        "yitro": "Yitro",
        "mishpatim": "Mishpatim",
        "terumah": "Terumah",
        "tetzaveh": "Tetzaveh",
        "ki-tisa": "Ki Tisa",
        "vayakhel": "Vayakhel",
        "pekudei": "Pekudei",
        "vayakhel-pekudei": "Vayakhel\u{2013}Pekudei",
        "vayikra": "Vayikra",
        "tzav": "Tzav",
        "shemini": "Shemini",
        "tazria": "Tazria",
        "metzora": "Metzora",
        "tazria-metzora": "Tazria\u{2013}Metzora",
        "acharei-mot": "Acharei Mot",
        "kedoshim": "Kedoshim",
        "acharei-mot-kedoshim": "Acharei Mot\u{2013}Kedoshim",
        "emor": "Emor",
        "behar": "Behar",
        "bechukotai": "Bechukotai",
        "behar-bechukotai": "Behar\u{2013}Bechukotai",
        "bamidbar": "Bamidbar",
        "naso": "Naso",
        "behaalotecha": "Beha'alotecha",
        "shelach": "Shelach",
        "korach": "Korach",
        "chukat": "Chukat",
        "balak": "Balak",
        "chukat-balak": "Chukat\u{2013}Balak",
        "pinchas": "Pinchas",
        "matot": "Matot",
        "masei": "Masei",
        "matot-masei": "Matot\u{2013}Masei",
        "devarim": "Devarim",
        "vaetchanan": "Vaetchanan",
        "eikev": "Eikev",
        "reeh": "Re'eh",
        "shoftim": "Shoftim",
        "ki-teitzei": "Ki Teitzei",
        "ki-tavo": "Ki Tavo",
        "nitzavim": "Nitzavim",
        "vayelech": "Vayelech",
        "nitzavim-vayelech": "Nitzavim\u{2013}Vayelech",
        "haazinu": "Ha'azinu",
        "vzot-haberachah": "V'Zot HaBerachah"
    ]

    /// Returns a human-readable display name for a canonical parsha key. Doubled parshiot
    /// are formatted with an en-dash.
    static func displayName(forKey key: String) -> String {
        displayNames[key] ?? key.capitalized
    }

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

    /// Maps a combined parsha key to its component single keys, so callers can match a
    /// requested single (e.g. "vayakhel") against a year that reads it combined
    /// (e.g. "vayakhel-pekudei").
    private static let combinedKeyComponents: [String: [String]] = [
        "vayakhel-pekudei": ["vayakhel", "pekudei"],
        "tazria-metzora": ["tazria", "metzora"],
        "acharei-mot-kedoshim": ["acharei-mot", "kedoshim"],
        "behar-bechukotai": ["behar", "bechukotai"],
        "chukat-balak": ["chukat", "balak"],
        "matot-masei": ["matot", "masei"],
        "nitzavim-vayelech": ["nitzavim", "vayelech"]
    ]

    /// Returns every Shabbat in the Hebrew year containing `date`, paired with its parsha
    /// key (nil on festival-displaced Shabbatot) and the festival name (when displaced).
    /// Walks from the first sedra Shabbat after Simchat Torah through next Rosh Hashanah.
    static func shabbatotForHebrewYear(containing date: Date)
        -> [(date: Date, parshaKey: String?, festivalName: String?)] {
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

            var results: [(date: Date, parshaKey: String?, festivalName: String?)] = []
            while current < nextRH {
                let key = parshaKey(forShabbat: current)
                let festival = displacingFestivalName(forShabbat: current)
                results.append((current, key, festival))
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

    // MARK: - Year-Type Schedules (Diaspora)

    /// Returns the Gregorian date of Simchat Torah (23 Tishri) for a given Hebrew year.
    private static func simchatTorahDate(hebYear: Int, hebrew: Calendar, gregorian: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = hebYear
        comps.month = 1 // Tishri
        comps.day = 23
        guard let date = hebrew.date(from: comps) else { return nil }
        return gregorian.startOfDay(for: date)
    }

    /// Generates the diaspora sedra schedule for a Hebrew year, mapping weekIndex
    /// (0 = first post-Simchat-Torah Shabbat) to the parsha key read that week.
    /// This uses a compact algorithm that walks the 54-parsha cycle and applies the
    /// standard doubled-parshah and festival-displacement rules for the year type.
    private static func sedraSchedule(hebYear: Int, hebrew: Calendar, gregorian: Calendar) -> [String]? {
        // Memoized: the schedule depends only on the Hebrew year, but the caller asks
        // for it once per Shabbat. Without this, rendering a year costs ~52 full
        // schedule builds instead of one.
        if let cached = scheduleCache[hebYear] { return cached }
        let built = buildSedraScheduleUncached(hebYear: hebYear, hebrew: hebrew, gregorian: gregorian)
        scheduleCache[hebYear] = built
        return built
    }

    private static func buildSedraScheduleUncached(
        hebYear: Int,
        hebrew: Calendar,
        gregorian: Calendar
    ) -> [String]? {
        guard let roshHashanah = roshHashanahDate(hebYear: hebYear, hebrew: hebrew, gregorian: gregorian),
              let nextRoshHashanah = roshHashanahDate(hebYear: hebYear + 1, hebrew: hebrew, gregorian: gregorian) else {
            return nil
        }

        let rhWeekday = gregorian.component(.weekday, from: roshHashanah) // 1..7
        let isLeap = isHebrewLeapYear(hebYear)

        // Year length: 0 = INCOMPLETE (353/383 days), 1 = REGULAR (354/384), 2 = COMPLETE (355/385).
        // (353|383) % 30 == 23, (354|384) % 30 == 24, (355|385) % 30 == 25.
        let dayCount = gregorian.dateComponents([.day], from: roshHashanah, to: nextRoshHashanah).day ?? 0
        let yearLength: Int
        switch dayCount % 30 {
        case 23: yearLength = 0
        case 24: yearLength = 1
        case 25: yearLength = 2
        default: return nil
        }

        return buildSedraSchedule(
            rhWeekday: rhWeekday,
            isLeap: isLeap,
            yearLength: yearLength,
            simchatTorah: simchatTorahDate(hebYear: hebYear, hebrew: hebrew, gregorian: gregorian) ?? roshHashanah,
            nextRoshHashanah: nextRoshHashanah,
            gregorian: gregorian
        )
    }

    private static func roshHashanahDate(hebYear: Int, hebrew: Calendar, gregorian: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = hebYear
        comps.month = 1 // Tishri
        comps.day = 1
        guard let date = hebrew.date(from: comps) else { return nil }
        return gregorian.startOfDay(for: date)
    }

    private static func isHebrewLeapYear(_ hebYear: Int) -> Bool {
        // Leap years in the 19-year cycle: 3, 6, 8, 11, 14, 17, 19 (= 0 mod 19).
        let pos = ((hebYear - 1) % 19) + 1
        return [3, 6, 8, 11, 14, 17, 19].contains(pos)
    }

    /// Builds the parsha-per-Shabbat list for a given year type, applying
    /// doubled-parshah rules and festival displacement for diaspora reading.
    private static func buildSedraSchedule(
        rhWeekday: Int,
        isLeap: Bool,
        yearLength: Int,
        simchatTorah: Date,
        nextRoshHashanah: Date,
        gregorian: Calendar
    ) -> [String] {
        // The seven doubled-parshah pairs. In the annual cycle we emit each pair either
        // as two separate keys (when the year is "long enough") or as a single combined
        // key, per the Four Gates table for the diaspora reading cycle.
        let combine: [String: Bool] = doubledCombinations(
            rhWeekday: rhWeekday, isLeap: isLeap, yearLength: yearLength
        )

        // Pairs keyed by the first parsha of each (identical to the dash-joined key).
        let pairMap: [(first: String, second: String, combined: String)] = [
            ("vayakhel", "pekudei", "vayakhel-pekudei"),
            ("tazria", "metzora", "tazria-metzora"),
            ("acharei-mot", "kedoshim", "acharei-mot-kedoshim"),
            ("behar", "bechukotai", "behar-bechukotai"),
            ("chukat", "balak", "chukat-balak"),
            ("matot", "masei", "matot-masei"),
            ("nitzavim", "vayelech", "nitzavim-vayelech")
        ]
        let pairFirsts = Set(pairMap.map(\.first))
        let pairByFirst = Dictionary(uniqueKeysWithValues: pairMap.map { ($0.first, $0) })

        // Walk the canonical cycle, emitting one entry per Shabbat in the schedule,
        // merging pairs when the year-type lookup says to, and skipping Shabbatot that
        // fall on displacing festivals.
        var schedule: [String] = []
        var cycleIndex = 0
        var shabbat = advanceToFirstSedraShabbat(from: simchatTorah, gregorian: gregorian)

        while shabbat < nextRoshHashanah, cycleIndex < allParshaKeys.count {
            let key = allParshaKeys[cycleIndex]

            // If this Shabbat is displaced by a festival reading, emit the last-known
            // parsha key as a placeholder (so week counts stay aligned) and advance
            // the Shabbat without advancing the cycle index. For V1 we use a
            // conservative check: skip only if the Shabbat equals one of the listed
            // displacing dates for the year.
            if isDisplacedShabbat(shabbat, rhWeekday: rhWeekday, isLeap: isLeap, gregorian: gregorian) {
                // On a displaced Shabbat, no weekly parsha is read. We still emit a
                // value so the downstream weekIndex mapping stays correct — use the
                // previous parsha key, or the current one if we're at the start.
                schedule.append(schedule.last ?? key)
                shabbat = gregorian.date(byAdding: .day, value: 7, to: shabbat) ?? shabbat
                continue
            }

            if pairFirsts.contains(key), let pair = pairByFirst[key], combine[key] == true {
                schedule.append(pair.combined)
                cycleIndex += 2
            } else {
                schedule.append(key)
                cycleIndex += 1
            }
            shabbat = gregorian.date(byAdding: .day, value: 7, to: shabbat) ?? shabbat
        }

        return schedule
    }

    /// Returns the first Shabbat on or after `simchatTorah + 1 day` that carries a
    /// weekly Torah reading (Bereishit).
    private static func advanceToFirstSedraShabbat(from simchatTorah: Date, gregorian: Calendar) -> Date {
        let dayAfter = gregorian.date(byAdding: .day, value: 1, to: simchatTorah) ?? simchatTorah
        return shabbatOfWeek(containing: dayAfter, calendar: gregorian)
    }

    /// First-parsha key of each doubled pair, in canonical-cycle order, mapped to that
    /// pair's first-parsha index in `allParshaKeys`.
    private static let pairFirstKeyToIndex: [String: Int] = [
        "vayakhel": 21,
        "tazria": 26,
        "acharei-mot": 28,
        "behar": 31,
        "chukat": 38,
        "matot": 41,
        "nitzavim": 50
    ]

    /// The diaspora "Four Gates" combination table. Keys encode a year type as
    /// `"<leap><rhWeekday><yearLength>"` (with an optional trailing `0` for diaspora
    /// when the same `<leap><rhWeekday><yearLength>` triple has different combinations
    /// in Israel vs. diaspora). The value is the set of parsha-cycle indices whose
    /// pair combines this year. Indices match `pairFirstKeyToIndex`. Mirrors the
    /// reference data used by hebcal/hdate. Year types not listed are impossible
    /// combinations (e.g. non-leap with Rosh Hashanah on Tuesday and a complete year).
    private static let diasporaCombinedPairsByYearType: [String: Set<Int>] = [
        // Non-leap
        "020": [21, 26, 28, 31, 41, 50],         // RH=Mon, Incomplete
        "0220": [21, 26, 28, 31, 38, 41, 50],     // RH=Mon, Complete
        "0310": [21, 26, 28, 31, 38, 41, 50],     // RH=Tue, Regular  (= 0220)
        "0510": [21, 26, 28, 31, 41],             // RH=Thu, Regular
        "052": [26, 28, 31, 41],                 // RH=Thu, Complete
        "070": [21, 26, 28, 31, 41],             // RH=Sat, Incomplete
        "072": [21, 26, 28, 31, 41, 50],         // RH=Sat, Complete
        // Leap
        "1200": [38, 41, 50],                     // RH=Mon, Incomplete
        "1220": [41],                             // RH=Mon, Complete
        "1310": [41],                             // RH=Tue, Regular  (= 1220)
        "150": [],                               // RH=Thu, Incomplete
        "152": [50],                             // RH=Thu, Complete
        "170": [41, 50],                         // RH=Sat, Incomplete
        "1720": [38, 41, 50]                      // RH=Sat, Complete
    ]

    /// Returns, for each doubled-pair first-key, whether that pair combines this year.
    /// Looks up the year type in the diaspora Four Gates table.
    private static func doubledCombinations(rhWeekday: Int, isLeap: Bool, yearLength: Int) -> [String: Bool] {
        let baseKey = "\(isLeap ? 1 : 0)\(rhWeekday)\(yearLength)"
        let combinedIndices: Set<Int> = diasporaCombinedPairsByYearType[baseKey]
            ?? diasporaCombinedPairsByYearType[baseKey + "0"]
            ?? []
        return Dictionary(
            uniqueKeysWithValues: pairFirstKeyToIndex.map { (key, index) in
                (key, combinedIndices.contains(index))
            }
        )
    }

    /// Returns true if `shabbat` coincides with a festival that displaces the weekly
    /// parsha in diaspora. The displacing windows (any Shabbat falling within them):
    ///   - Tishri  15-22   (Sukkot through Shemini Atzeret)
    ///   - Nisan   15-22   (Pesach through Pesach VIII, including any Chol HaMoed Shabbat)
    ///   - Sivan   6-7     (Shavuot day 1 / day 2)
    /// Foundation's Hebrew calendar uses fixed month numbers across leap and non-leap
    /// years: Tishri=1, Cheshvan=2, Kislev=3, Tevet=4, Shevat=5, Adar I=6 (leap only),
    /// Adar (non-leap) / Adar II (leap)=7, Nisan=8, Iyar=9, Sivan=10, Tammuz=11, Av=12,
    /// Elul=13. In non-leap years month 6 is simply skipped — so Nisan and Sivan are
    /// always 8 and 10 regardless of leap status.
    private static func isDisplacedShabbat(_ shabbat: Date, rhWeekday: Int, isLeap: Bool, gregorian: Calendar) -> Bool {
        let comps = hebrew.dateComponents([.year, .month, .day], from: shabbat)
        guard let month = comps.month, let day = comps.day else { return false }

        if month == 1, (15...22).contains(day) { return true }   // Tishri
        if month == 8, (15...22).contains(day) { return true }   // Nisan
        if month == 10, day == 6 || day == 7 { return true }     // Sivan
        return false
    }
}
