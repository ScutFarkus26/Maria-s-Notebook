// TodayGoneQuiet.swift
// The words and thresholds of Today's Gone quiet section.
//
// Gone quiet is open work nobody has touched in `AgingPolicy.staleDays`
// school days or more, most quiet first. The view model keeps the top
// `TodayScheduleBuilder.staleRowLimit` rows but knows the true count
// (`staleTotalCount`), so the header's "See all N" names every one of them,
// not just the rows on screen. A row's age chip reads "19d quiet" and turns
// orange from `longQuietDays`.
//
// Pure: counts in, strings and flags out.

import Foundation

nonisolated enum TodayGoneQuiet {

    /// From here the age chip is orange: nearly four school weeks untouched.
    static let longQuietDays = 18

    static let title = "Gone quiet"

    /// "open work nobody has touched in 10+ days".
    static var subtitle: String {
        "open work nobody has touched in \(AgingPolicy.staleDays)+ days"
    }

    /// "See all 23" — the true count, which can be more than the rows shown.
    static func seeAllText(totalCount: Int) -> String {
        "See all \(totalCount)"
    }

    /// "19d quiet".
    static func ageText(days: Int) -> String {
        "\(days)d quiet"
    }

    /// The age chip turns orange from `longQuietDays`.
    static func isLongQuiet(days: Int) -> Bool {
        days >= longQuietDays
    }
}
