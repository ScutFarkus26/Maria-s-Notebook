// SpecialShabbatService.swift
// Identifies which (if any) "special Shabbat" applies to a given Shabbat
// in the diaspora calendar.

import Foundation

enum SpecialShabbat: String, CaseIterable, Sendable {
    case hagadol
    case hachodesh
    case parah
    case zachor
    case shekalim
    case chazon
    case nachamu
    case shuvah
    case shirah
    case roshChodesh
    case macharChodesh

    var displayName: String {
        switch self {
        case .hagadol: return "Shabbat HaGadol"
        case .hachodesh: return "Shabbat HaChodesh"
        case .parah: return "Shabbat Parah"
        case .zachor: return "Shabbat Zachor"
        case .shekalim: return "Shabbat Shekalim"
        case .chazon: return "Shabbat Chazon"
        case .nachamu: return "Shabbat Nachamu"
        case .shuvah: return "Shabbat Shuvah"
        case .shirah: return "Shabbat Shirah"
        case .roshChodesh: return "Shabbat Rosh Chodesh"
        case .macharChodesh: return "Shabbat Machar Chodesh"
        }
    }

    var specialReading: String? {
        switch self {
        case .hagadol: return "Haftarah: Malachi 3:4–24 (the great Shabbat before Pesach)"
        case .hachodesh: return "Maftir: Exodus 12:1–20 · Haftarah: Ezekiel 45:16–46:18"
        case .parah: return "Maftir: Numbers 19:1–22 · Haftarah: Ezekiel 36:16–38"
        case .zachor: return "Maftir: Deuteronomy 25:17–19 · Haftarah: I Samuel 15:2–34"
        case .shekalim: return "Maftir: Exodus 30:11–16 · Haftarah: II Kings 12:1–17"
        case .chazon: return "Haftarah: Isaiah 1:1–27 (Vision of Isaiah, before Tisha B’Av)"
        case .nachamu: return "Haftarah: Isaiah 40:1–26 (Comfort, comfort My people)"
        case .shuvah: return "Haftarah: Hosea 14:2–10, Joel 2:15–27, Micah 7:18–20"
        case .shirah: return "Includes the Song at the Sea (Exodus 15)"
        case .roshChodesh: return "Maftir: Numbers 28:9–15 · Haftarah: Isaiah 66"
        case .macharChodesh: return "Haftarah: I Samuel 20:18–42 (Tomorrow is the new moon)"
        }
    }
}

@MainActor
enum SpecialShabbatService {

    /// Returns the most-specific special-Shabbat designation that applies to `shabbat`,
    /// or `nil` if it is an ordinary Shabbat.
    static func specialShabbat(forShabbat shabbat: Date) -> SpecialShabbat? {
        let gregorian = Calendar(identifier: .gregorian)
        let hebrew = Calendar(identifier: .hebrew)
        let shabbat = gregorian.startOfDay(for: shabbat)

        let comps = hebrew.dateComponents([.year, .month, .day], from: shabbat)
        guard let hebYear = comps.year, let hebMonth = comps.month, let hebDay = comps.day else {
            return nil
        }

        // Hebrew landmark dates for the Hebrew year containing `shabbat`.
        let rcAdarFinal = hebrewDate(year: hebYear, month: 7, day: 1, hebrew: hebrew, gregorian: gregorian)
        let purim = hebrewDate(year: hebYear, month: 7, day: 14, hebrew: hebrew, gregorian: gregorian)
        let rcNisan = hebrewDate(year: hebYear, month: 8, day: 1, hebrew: hebrew, gregorian: gregorian)
        let pesach = hebrewDate(year: hebYear, month: 8, day: 15, hebrew: hebrew, gregorian: gregorian)

        let weekEnd = gregorian.date(byAdding: .day, value: 7, to: shabbat) ?? shabbat
        // Target on or after `shabbat`, strictly before the next Shabbat.
        let onOrAfterShabbat: (Date?) -> Bool = { target in
            guard let t = target else { return false }
            return t >= shabbat && t < weekEnd
        }
        // Target after `shabbat`, on or before the next Shabbat.
        let strictlyAfter: (Date?) -> Bool = { target in
            guard let t = target else { return false }
            return t > shabbat && t <= weekEnd
        }

        // Precedence: more-specific date-based Shabbatot first.
        if strictlyAfter(pesach) { return .hagadol }
        if onOrAfterShabbat(rcNisan) { return .hachodesh }
        if let p = purim, let n = rcNisan, p < shabbat, shabbat < n {
            return .parah
        }
        if strictlyAfter(purim) { return .zachor }
        if onOrAfterShabbat(rcAdarFinal) { return .shekalim }

        // Parsha-tied special Shabbatot.
        let parshaKey = HebrewParshaService.parshaKey(forShabbat: shabbat)
        if parshaKey == "devarim" { return .chazon }
        if parshaKey == "vaetchanan" { return .nachamu }

        // Shuvah: between Rosh Hashanah (1 Tishri) and Yom Kippur (10 Tishri).
        if hebMonth == 1, (3...9).contains(hebDay) {
            return .shuvah
        }

        if parshaKey == "beshalach" { return .shirah }

        // Rosh Chodesh: day 1 (always RC), or day 30 of the prior month (first day
        // of a two-day RC). Foundation's Hebrew calendar yields day == 1 on the
        // first day of a month and day == 30 only when the month length is 30.
        if hebDay == 1 || hebDay == 30 {
            return .roshChodesh
        }

        // Machar Chodesh: Shabbat is the day before Rosh Chodesh.
        if hebDay == 29 {
            let nextDay = gregorian.date(byAdding: .day, value: 1, to: shabbat) ?? shabbat
            let nextDayComps = hebrew.dateComponents([.day], from: nextDay)
            if nextDayComps.day == 1 || nextDayComps.day == 30 {
                return .macharChodesh
            }
        }

        return nil
    }

    private static func hebrewDate(year: Int, month: Int, day: Int,
                                   hebrew: Calendar, gregorian: Calendar) -> Date? {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        guard let d = hebrew.date(from: c) else { return nil }
        return gregorian.startOfDay(for: d)
    }
}
