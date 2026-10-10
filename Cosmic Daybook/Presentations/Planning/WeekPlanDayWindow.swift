// WeekPlanDayWindow.swift
// When and how the Scheduled strip loads more days at its ends, kept apart
// from the view so both can be tested.
//
// Adding days in front of the strip moves every day after them along. Apple
// promises to keep a scroll view's identified day in place when it reorders or
// resizes, but says nothing about days inserted before it, so the strip can't
// count on staying put. It grows only once scrolling has come to rest, puts the
// day that was leading back explicitly, and ignores its own moves while it does.

import Foundation

enum WeekPlanDayWindow {

    /// How near each end the leading day may come before more days load there.
    struct Margins: Equatable {
        /// Days that may remain before the leading day.
        var front: Int
        /// Days, counting the leading day, that may remain from it to the end:
        /// a screen's worth plus some, so the far end never shows empty.
        var back: Int
    }

    /// The window after loading more days at one end or both.
    struct Growth: Equatable {
        var days: [Date]
        /// The day to keep at the leading edge: the one that was there before.
        var leadingDay: Date
        var addedInFront: Int
        var addedAtEnd: Int
    }

    /// The window grown at whichever end `leadingDay` is near, or nil when
    /// it is near neither (or there are no more school days to add).
    ///
    /// - Parameters:
    ///   - margins: How near either end the leading day may come first.
    ///   - earlierDays: School days before the window's first day.
    ///   - laterDays: School days after the window's last day.
    static func grown(
        days: [Date],
        leadingDay: Date,
        margins: Margins,
        earlierDays: (_ first: Date) -> [Date],
        laterDays: (_ last: Date) -> [Date]
    ) -> Growth? {
        guard let index = days.firstIndex(of: leadingDay),
              let first = days.first, let last = days.last else { return nil }
        var grownDays = days
        var addedInFront = 0
        var addedAtEnd = 0
        if index < margins.front {
            let earlier = earlierDays(first).filter { $0 < first }
            grownDays.insert(contentsOf: earlier, at: 0)
            addedInFront = earlier.count
        }
        if days.count - index < margins.back {
            let later = laterDays(last).filter { $0 > last }
            grownDays.append(contentsOf: later)
            addedAtEnd = later.count
        }
        guard addedInFront + addedAtEnd > 0 else { return nil }
        return Growth(days: grownDays, leadingDay: leadingDay, addedInFront: addedInFront, addedAtEnd: addedAtEnd)
    }

    /// Whether the strip may look at its ends now: only at rest, and never
    /// while it is putting the leading day back after days were added in front.
    struct Settle: Equatable {
        private(set) var isScrolling = false
        /// The day being held at the leading edge while days go in front of it.
        private(set) var pinnedDay: Date?

        /// The guide may be scrolling, a move may be animating, or the strip
        /// may be putting a day back: in each case, wait.
        var canSettle: Bool { !isScrolling && pinnedDay == nil }

        /// Records the scroll phase. True when scrolling has just come to
        /// rest, which is the one moment a scroll checks the ends. Coming to
        /// rest also lets go of a held day: wherever the strip stopped is now
        /// the guide's.
        mutating func scrollPhaseChanged(isScrolling now: Bool) -> Bool {
            let cameToRest = isScrolling && !now
            isScrolling = now
            if cameToRest { pinnedDay = nil }
            return cameToRest
        }

        /// The scroll view reported a new leading day. True when the strip is
        /// at rest and the report is the guide's (or a move made for her), so
        /// the ends may be checked. While a day is held, every report is the
        /// strip's own shuffling as the new days lay out and is ignored, until
        /// one names the held day, which lets go of it.
        mutating func leadingDayReported(_ day: Date?) -> Bool {
            guard let pinnedDay else { return !isScrolling }
            if day == pinnedDay { self.pinnedDay = nil }
            return false
        }

        mutating func pin(_ day: Date) { pinnedDay = day }

        /// Lets go of `day` if it is still held: the safety cap, so a hold the
        /// scroll view never answers can't stop the strip growing for good.
        mutating func releasePin(holding day: Date) {
            if pinnedDay == day { pinnedDay = nil }
        }

        mutating func releasePin() { pinnedDay = nil }
    }
}
