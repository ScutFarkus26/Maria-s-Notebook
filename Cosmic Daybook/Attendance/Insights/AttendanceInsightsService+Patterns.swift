// AttendanceInsightsService+Patterns.swift
// The sidebar's Patterns: children with absences or late arrivals, with
// siblings gathered into one family, since one conversation with a family
// covers all of its children.

import Foundation
import CoreData

/// One line in Patterns: a child, or a family of two or more on the list.
struct AttendancePattern: Identifiable, Equatable {
    /// "Fleischmann" for a family; nil for one child.
    let familyName: String?
    /// The children, most absences and late arrivals first.
    let members: [AttendanceWatchListEntry]

    var id: String { members.map(\.studentID.uuidString).joined(separator: "+") }
    var absentCount: Int { members.reduce(0) { $0 + $1.absentCount } }
    var tardyCount: Int { members.reduce(0) { $0 + $1.tardyCount } }
    var score: Int { absentCount * 2 + tardyCount }
}

extension AttendanceInsightsService {

    /// Gathers `entries` into patterns: children sharing a family key (the
    /// same guardian email, else the same last name) become one family when
    /// two or more of them are on the list. The `limit` biggest come back,
    /// a family counting once.
    static func patterns(
        _ entries: [AttendanceWatchListEntry],
        familyKey: (UUID) -> String?,
        familyName: (UUID) -> String,
        limit: Int
    ) -> [AttendancePattern] {
        var byFamily: [String: [AttendanceWatchListEntry]] = [:]
        var loners: [AttendanceWatchListEntry] = []
        for entry in entries {
            if let key = familyKey(entry.studentID) {
                byFamily[key, default: []].append(entry)
            } else {
                loners.append(entry)
            }
        }
        var patterns = loners.map { AttendancePattern(familyName: nil, members: [$0]) }
        for members in byFamily.values {
            let ordered = members.sorted { ($0.absentCount * 2 + $0.tardyCount) > ($1.absentCount * 2 + $1.tardyCount) }
            if ordered.count > 1, let first = ordered.first {
                patterns.append(AttendancePattern(familyName: familyName(first.studentID), members: ordered))
            } else {
                patterns += ordered.map { AttendancePattern(familyName: nil, members: [$0]) }
            }
        }
        return patterns
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return (lhs.familyName ?? lhs.members[0].fullName)
                    .localizedCaseInsensitiveCompare(rhs.familyName ?? rhs.members[0].fullName) == .orderedAscending
            }
            .prefix(limit)
            .map(\.self)
    }

    /// Each student's family key: their guardians' email addresses when any
    /// are on file (siblings share a parent's), else their last name.
    static func familyKeys(for students: [CDStudent], context: NSManagedObjectContext) -> [UUID: String] {
        let ids = students.compactMap { $0.id?.uuidString }
        let request = CDFetchRequest(CDGuardian.self)
        request.predicate = NSPredicate(format: "studentID IN %@", ids)
        var emails: [String: Set<String>] = [:]
        for guardian in context.safeFetch(request) {
            let email = guardian.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty else { continue }
            emails[guardian.studentID, default: []].insert(email)
        }
        var keys: [UUID: String] = [:]
        for student in students {
            guard let id = student.id else { continue }
            if let found = emails[id.uuidString], let first = found.min() {
                keys[id] = "email:" + first
            } else {
                let last = student.lastName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    .trimmingCharacters(in: .whitespaces)
                if !last.isEmpty { keys[id] = "name:" + last }
            }
        }
        return keys
    }
}
