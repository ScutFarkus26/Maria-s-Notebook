// WaitingStudentBands.swift
// Which of the waiting rail's three groups each child falls in.
//
// The rail used to color every row by age, and on a class that had gone two
// weeks without lessons every row came out the same red, which said nothing.
// Grouping says it instead: the children past the long-wait line at the top
// (the only ones whose numbers are colored), then those who have waited a week
// or more, then everyone else folded into one line that opens in place.
//
// The long-wait line is not a new number. It is the guide's own overdue
// setting, the same one that turns a presentation card red beside the rail, so
// red means one thing on the whole screen.
//
// Kept free of SwiftUI so the bucketing — which decides who is in plain view
// and who is folded away — can be tested directly.

import Foundation

/// One of the rail's three groups, in the order they are shown.
enum WaitingStudentBand: CaseIterable, Sendable {
    /// Past the guide's overdue threshold, or never taught at all.
    case longWait
    /// A school week or more, but not yet overdue.
    case aWeekOrMore
    /// Everyone else, folded into one line by default.
    case underAWeek
}

/// A waiting list split into its three groups, each still in the list's order.
struct WaitingStudentBands {
    /// Five school days: the line between "a week or more" and "under a week".
    static let schoolWeek = 5

    static let aWeekOrMoreTitle = "A week or more"
    static let underAWeekTitle = "Under a week"

    /// The guide's overdue setting, clamped the way `StudentAgePalette` clamps
    /// it, so a child is in the top group exactly when their number is red.
    let longWaitThreshold: Int
    let longWait: [WaitingStudent]
    let aWeekOrMore: [WaitingStudent]
    let underAWeek: [WaitingStudent]

    /// Splits `entries` without reordering them: the list arrives already
    /// sorted by `WaitingStudentsOrder`, and each group keeps that order.
    init(_ entries: [WaitingStudent], longWaitThreshold: Int) {
        let threshold = max(0, longWaitThreshold)
        var longWait: [WaitingStudent] = []
        var aWeekOrMore: [WaitingStudent] = []
        var underAWeek: [WaitingStudent] = []
        for entry in entries {
            switch Self.band(forDays: entry.daysWaiting, longWaitThreshold: threshold) {
            case .longWait: longWait.append(entry)
            case .aWeekOrMore: aWeekOrMore.append(entry)
            case .underAWeek: underAWeek.append(entry)
            }
        }
        self.longWaitThreshold = threshold
        self.longWait = longWait
        self.aWeekOrMore = aWeekOrMore
        self.underAWeek = underAWeek
    }

    /// The group for a child who has waited `days` school days, or `nil` days
    /// if they have never been taught.
    ///
    /// Never-taught children go to the top: they are the longest wait there
    /// is, not a missing number. When the threshold is a week or less the
    /// middle group is simply empty, because nobody can be a week late without
    /// already being overdue.
    static func band(forDays days: Int?, longWaitThreshold: Int) -> WaitingStudentBand {
        guard let days else { return .longWait }
        if days >= max(0, longWaitThreshold) { return .longWait }
        if days >= schoolWeek { return .aWeekOrMore }
        return .underAWeek
    }

    /// The top group's label, written from the guide's own threshold so the
    /// label and the red numbers under it can never disagree.
    var longWaitTitle: String {
        "\(longWaitThreshold)+ school days"
    }

    /// The single line that stands in for the folded group.
    var underAWeekSummary: String {
        "\(underAWeek.count) more, under a week"
    }

    /// Whether anyone is above the fold. When nobody is, folding the rest away
    /// would leave the rail showing nothing but a line saying it is hiding
    /// everyone, so the last group is shown open instead.
    var hasChildrenAboveTheFold: Bool {
        !longWait.isEmpty || !aWeekOrMore.isEmpty
    }
}
