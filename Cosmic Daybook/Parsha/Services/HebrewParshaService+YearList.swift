// HebrewParshaService+YearList.swift
// The list the parsha screen shows for a reading cycle: its Shabbatot, then Simchat Torah,
// where V'Zot HaBerachah is read. No Shabbat ever carries V'Zot HaBerachah, so without this
// row the lessons tagged to it could not be reached from the parsha screen.

import Foundation

extension HebrewParshaService {

    /// The canonical key of the last reading in the cycle, read on Simchat Torah.
    static let vzotHaberachahKey = "vzot-haberachah"

    /// Whether `date` is Simchat Torah (23 Tishri, diaspora).
    static func isSimchatTorah(_ date: Date) -> Bool {
        let comps = hebrew.dateComponents([.month, .day], from: date)
        return comps.month == 1 && comps.day == 23
    }

    /// The first Simchat Torah after `date`: the day the cycle that `date` belongs to ends.
    static func simchatTorahClosingCycle(after date: Date) -> Date? {
        guard let hebYear = hebrew.dateComponents([.year], from: date).year else { return nil }
        for year in [hebYear, hebYear + 1] {
            if let simchatTorah = simchatTorahDate(hebYear: year, hebrew: hebrew, gregorian: gregorian),
               simchatTorah > date {
                return simchatTorah
            }
        }
        return nil
    }

    /// What the year list shows when opened on `now`: the cycle's Shabbatot and, last, Simchat
    /// Torah with V'Zot HaBerachah.
    ///
    /// A cycle's Shabbatot run from Bereishit to the last Shabbat before the next Simchat Torah
    /// (Ha'azinu and Sukkot included), so in the few days after that Shabbat the cycle is
    /// already over and listing it showed a year of past readings; the list shows the coming
    /// cycle then. (A month on always lands in the coming cycle.)
    static func parshaYearList(on now: Date = Date()) -> [ShabbatEntry] {
        var shabbatot = shabbatotForHebrewYear(containing: now)
        let today = gregorian.startOfDay(for: now)
        if let last = shabbatot.last, last.date < today,
           let monthOn = gregorian.date(byAdding: .day, value: 30, to: now) {
            shabbatot = shabbatotForHebrewYear(containing: monthOn)
        }
        if let last = shabbatot.last, let simchatTorah = simchatTorahClosingCycle(after: last.date) {
            shabbatot.append(ShabbatEntry(date: simchatTorah, parshaKey: vzotHaberachahKey, festivalName: nil))
        }
        return shabbatot
    }
}
