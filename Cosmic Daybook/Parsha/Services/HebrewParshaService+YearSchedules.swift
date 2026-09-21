// HebrewParshaService+YearSchedules.swift
// Four Gates year-type schedules: which parshiot are read, in what order, and
// which doubled pairs are combined for a given Hebrew year type.

import Foundation

extension HebrewParshaService {

    // MARK: - Year-Type Schedules (Diaspora)

    /// Returns the Gregorian date of Simchat Torah (23 Tishri) for a given Hebrew year.
    static func simchatTorahDate(hebYear: Int, hebrew: Calendar, gregorian: Calendar) -> Date? {
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
    static func sedraSchedule(hebYear: Int, hebrew: Calendar, gregorian: Calendar) -> [String]? {
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
