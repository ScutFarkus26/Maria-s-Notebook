// ChecklistLessonFilter.swift
// Text matching for the checklist's lesson filter field.
//
// Deliberately free of Core Data so the matching rules can be exercised directly
// in tests — the view model applies these to CDLesson.

import Foundation

/// Matches lessons against the checklist filter field.
///
/// The query is split on whitespace and every token has to appear somewhere in the
/// lesson's name, sequence, or section, so "frac add" finds "Addition of Fractions"
/// without the guide having to recall the exact wording. Matching ignores case and
/// diacritics. Only the three fields the grid actually shows are searched — matching
/// write-ups would surface rows whose titles look unrelated.
enum ChecklistLessonFilter {

    /// Splits a raw query into the tokens a lesson has to match.
    /// A blank query yields no tokens, which callers read as "no filter".
    static func tokens(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// True when every token appears in at least one of the lesson's display fields.
    static func matches(tokens: [String], name: String, sequence: String, section: String) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = [name, sequence, section].joined(separator: "\n")
        return tokens.allSatisfy { token in
            haystack.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// A count of lessons matching the checklist filter inside one curriculum area.
/// The grid only ever shows one area, so this is what lets the empty state point at
/// the areas that do hold matches instead of dead-ending.
struct ChecklistAreaMatchCount: Identifiable, Hashable, Sendable {
    let area: String
    let count: Int
    var id: String { area }
}
