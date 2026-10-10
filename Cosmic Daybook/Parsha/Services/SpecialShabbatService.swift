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

enum SpecialShabbatService {

    /// Returns the most-specific special-Shabbat designation that applies to `shabbat`,
    /// or `nil` if it is an ordinary Shabbat.
    static func specialShabbat(forShabbat shabbat: Date) -> SpecialShabbat? {
        let gregorian = HebrewParshaService.gregorian
        let hebrew = HebrewParshaService.hebrew
        let shabbat = gregorian.startOfDay(for: shabbat)

        let comps = hebrew.dateComponents([.year, .month, .day], from: shabbat)
        guard let hebYear = comps.year, let hebMonth = comps.month, let hebDay = comps.day else {
            return nil
        }

        if let seasonal = seasonalShabbat(shabbat, hebYear: hebYear) { return seasonal }

        // Parsha-tied special Shabbatot.
        let parshaKey = HebrewParshaService.parshaKey(forShabbat: shabbat)
        if parshaKey == "devarim" { return .chazon }
        if parshaKey == "vaetchanan" { return .nachamu }

        // Shuvah: between Rosh Hashanah (1 Tishri) and Yom Kippur (10 Tishri).
        if hebMonth == 1, (3...9).contains(hebDay) {
            return .shuvah
        }

        if parshaKey == "beshalach" { return .shirah }

        return newMoonShabbat(shabbat, hebMonth: hebMonth, hebDay: hebDay)
    }

    /// The four Shabbatot before Pesach (Shekalim, Zachor, Parah, HaChodesh) and
    /// HaGadol, from the year's Hebrew landmark dates.
    private static func seasonalShabbat(_ shabbat: Date, hebYear: Int) -> SpecialShabbat? {
        let gregorian = HebrewParshaService.gregorian
        let hebrew = HebrewParshaService.hebrew
        let rcAdarFinal = hebrewDate(year: hebYear, month: 7, day: 1, hebrew: hebrew, gregorian: gregorian)
        let purim = hebrewDate(year: hebYear, month: 7, day: 14, hebrew: hebrew, gregorian: gregorian)
        let rcNisan = hebrewDate(year: hebYear, month: 8, day: 1, hebrew: hebrew, gregorian: gregorian)
        let pesach = hebrewDate(year: hebYear, month: 8, day: 15, hebrew: hebrew, gregorian: gregorian)

        // `target` falls `from`...`until` days after `shabbat` (`from` included).
        let within: (Date?, Int, Int) -> Bool = { target, from, until in
            guard let target,
                  let lower = gregorian.date(byAdding: .day, value: from, to: shabbat),
                  let upper = gregorian.date(byAdding: .day, value: until, to: shabbat) else { return false }
            return target >= lower && target < upper
        }

        // Precedence: more-specific date-based Shabbatot first.
        if within(pesach, 1, 8) { return .hagadol }
        if within(rcNisan, 0, 7) { return .hachodesh }
        // Parah is the Shabbat right before HaChodesh's. "Any Shabbat between Purim
        // and Rosh Chodesh Nisan" also caught the Shabbat after a Friday Purim (and
        // after a Thursday Purim, when Pesach falls on Shabbat), which is ordinary.
        if within(rcNisan, 7, 14) { return .parah }
        if within(purim, 1, 8) { return .zachor }
        if within(rcAdarFinal, 0, 7) { return .shekalim }
        return nil
    }

    /// Shabbat Rosh Chodesh and Shabbat Machar Chodesh.
    private static func newMoonShabbat(_ shabbat: Date, hebMonth: Int, hebDay: Int) -> SpecialShabbat? {
        // Rosh Chodesh: day 1 (always RC), or day 30 of the prior month (first day
        // of a two-day RC). Foundation's Hebrew calendar yields day == 1 on the
        // first day of a month and day == 30 only when the month length is 30.
        // 1 Tishri is Rosh Hashanah, a festival of its own, not a Rosh Chodesh Shabbat.
        let isRoshHashanah = hebMonth == 1 && hebDay == 1
        if (hebDay == 1 || hebDay == 30) && !isRoshHashanah {
            return .roshChodesh
        }

        // Machar Chodesh: Shabbat is the day before Rosh Chodesh. (Rosh Hashanah
        // never falls on a Sunday, so 29 Elul is never a Shabbat.)
        guard hebDay == 29 else { return nil }
        let gregorian = HebrewParshaService.gregorian
        let nextDay = gregorian.date(byAdding: .day, value: 1, to: shabbat) ?? shabbat
        let nextDayComps = HebrewParshaService.hebrew.dateComponents([.day], from: nextDay)
        if nextDayComps.day == 1 || nextDayComps.day == 30 {
            return .macharChodesh
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
