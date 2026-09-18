// SuggestionRationale.swift
// Why a presentation is in Suggested Next.
//
// The scorer in `PresentationsViewModel+Filtering` weighs four things, and a
// pick the guide cannot account for is a pick they have to second-guess. So
// the same four factors are carried out of the scorer as plain values and
// worded here: the phrasing lives in one place, and it can be tested without
// Core Data.

import Foundation
import CoreData

struct SuggestionRationale: Equatable {

    /// The child who has gone longest without a presentation, among those on
    /// this card who aren't already booked for something. This is the factor
    /// that dominates the score, so it leads the sentence.
    var waitingChild: String?

    /// School days since that child's last presentation. `nil` alongside a
    /// non-nil `waitingChild` means they have never been taught.
    var waitingSchoolDays: Int?

    /// True when every child on the card already has a lesson scheduled, so
    /// the wait factor contributed nothing and the rank came from elsewhere.
    var everyoneAlreadyScheduled: Bool = false

    /// How long the presentation itself has sat in the inbox, in school days.
    var inboxSchoolDays: Int = 0

    /// Fewest open work items among the children who still need something —
    /// the ranking favours a child whose hands are free.
    var fewestOpenWork: Int?

    /// True when this lesson's area differs from the last area given to every
    /// one of those children.
    var changesArea: Bool = false

    /// Open work stops reading as a reason once a child has a pile of it.
    private static let openWorkMentionLimit = 2

    /// Short phrases, strongest factor first.
    var phrases: [String] {
        var result: [String] = []

        if everyoneAlreadyScheduled {
            result.append("everyone here is already booked")
        } else if let child = waitingChild {
            result.append("\(child) \(Self.waitPhrase(schoolDays: waitingSchoolDays))")
        }

        if inboxSchoolDays > 0 {
            result.append("\(Self.dayCount(inboxSchoolDays)) in the inbox")
        }

        if let open = fewestOpenWork, open <= Self.openWorkMentionLimit {
            result.append(open == 0
                          ? "no open work"
                          : "\(open) open work item\(open == 1 ? "" : "s")")
        }

        if changesArea {
            result.append("a change of area")
        }

        return result
    }

    /// One line for under the card. A pick can out-rank the rest without any
    /// one factor standing out, and saying nothing there would read as a bug.
    var summary: String {
        let parts = phrases
        guard !parts.isEmpty else { return "highest ranked of what is left" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Wording

    /// Matches the Waiting Longest rail, which is the other place on this
    /// screen that says how long a child has gone without a lesson.
    private static func waitPhrase(schoolDays: Int?) -> String {
        guard let days = schoolDays else { return "has never been taught" }
        switch days {
        case ...0: return "was taught today"
        case 1: return "was last taught 1 school day ago"
        default: return "was last taught \(days) school days ago"
        }
    }

    private static func dayCount(_ days: Int) -> String {
        days == 1 ? "1 school day" : "\(days) school days"
    }
}

// MARK: - One ranked pick

/// A presentation the ranking picked, paired with the reason it picked it.
/// The two travel together so a card and its explanation cannot disagree.
struct SuggestedPresentation {
    let assignment: CDLessonAssignment
    let rationale: SuggestionRationale

    var id: UUID? { assignment.id }
}
