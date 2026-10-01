// WeekPlanSection+Layout.swift
// How wide the week strip's days are, and what its range label says.
//
// Pure, so both rules are testable without drawing the strip.

import Foundation

extension WeekPlanSection {
    /// Narrowest a day column gets. Below it a presentation card's title and
    /// its row of chips stop fitting, so a pane too narrow for five days at
    /// this width (an iPhone, an iPad in split view) scrolls instead.
    ///
    /// 160, not 200: an 11-inch iPad in landscape leaves the strip about 900
    /// points beside the sidebar, and at 200 the fifth day was cut in half —
    /// the very thing the five-day strip is for. Titles wrap to two lines at
    /// this width and the chips wrap under them, which still reads.
    static let minimumColumnWidth: CGFloat = 160
    /// Space around the row of days and between neighboring days.
    static let stripPadding: CGFloat = 10
    static let columnSpacing: CGFloat = 10

    /// Each day's width when the strip is `stripWidth` points wide: an equal
    /// share of what the padding and gaps leave, so the whole school week is on
    /// screen at once, or `minimumColumnWidth` when that share is smaller.
    ///
    /// The days used to be a fixed ~730 points wide each (two lanes side by
    /// side), so a 1,500-point window showed a day and a half of the week the
    /// guide was planning.
    static func columnWidth(forStripWidth stripWidth: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0, stripWidth > 0 else { return minimumColumnWidth }
        let gaps = columnSpacing * CGFloat(dayCount - 1)
        let share = (stripWidth - stripPadding * 2 - gaps) / CGFloat(dayCount)
        return max(minimumColumnWidth, share.rounded(.down))
    }

    /// The header's range: exactly the first and last day the strip holds.
    ///
    /// "Sep 17 – 23" within a month, "Sep 28 – Oct 2" across two, and the year
    /// only when the range is not in this one. The interval style collapses
    /// the shared month the way the locale does, rather than a hand-built
    /// "start – end" that repeats it.
    static func rangeLabel(
        first: Date,
        last: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent,
        now: Date = Date()
    ) -> String {
        let thisYear = calendar.component(.year, from: now)
        let showsYear = calendar.component(.year, from: first) != thisYear
            || calendar.component(.year, from: last) != thisYear
        if calendar.isDate(first, inSameDayAs: last) || last < first {
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).day()
            if showsYear { style = style.year() }
            return first.formatted(style)
        }
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        if showsYear { style = style.year() }
        return (first..<last).formatted(style)
    }
}
