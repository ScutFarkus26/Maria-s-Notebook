// HistorySearch.swift
// What the search field in each History reads: the row's own words, and the
// names of the children on it, as the live lists already do. Apart from the
// views so the rules can be tested.

import Foundation

enum HistorySearch {

    /// The spellings of a child's name a search can hit: first, last, both,
    /// and the classroom short form ("Maya S").
    static func names(of student: CDStudent) -> [String] {
        [student.firstName, student.lastName, student.fullName, student.shortName]
    }

    /// Whether any of `texts` holds the typed `query` (case does not matter;
    /// an empty query keeps every row).
    static func matches(_ query: String, in texts: [String]) -> Bool {
        let query = query.trimmed().lowercased()
        guard !query.isEmpty else { return true }
        return texts.contains { $0.lowercased().contains(query) }
    }

    /// The children a work row is searched by: its owner, as the live list
    /// does; an offered row that no child has claimed yet, its participants.
    static func searchedStudentIDs(of work: CDWorkModel) -> [UUID] {
        if let owner = WorkGrouping.owner(of: work) { return [owner] }
        return WorkGrouping.studentIDs(of: work)
    }
}
