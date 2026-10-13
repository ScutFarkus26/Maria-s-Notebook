import Foundation

// Which ParentLocker child each notebook child is. A stored match
// (`parentLockerID`) decides; otherwise the names do, and only when exactly
// one ParentLocker child fits the notebook child and that ParentLocker child
// fits no other notebook child. A wrong match would send one child's mark to
// another, so anything less certain is left for the guide's Match Names.

nonisolated extension ParentLockerPlanner {

    enum Match: Sendable, Equatable {
        /// This ParentLocker `student_id`; `byName` when found by name this
        /// time rather than from the stored match.
        case matched(studentID: String, byName: Bool)
        case unmatched
        /// The ParentLocker children who fit, when more than one does (or the
        /// one who does also fits another notebook child).
        case ambiguous([String])
    }

    /// Every child's match against the children on `rosters`.
    static func match(children: [Child], rosters: [ParentLockerRoster]) -> [UUID: Match] {
        var people: [String: ParentLockerRosterStudent] = [:]
        for student in rosters.flatMap(\.students) where people[student.studentID] == nil {
            people[student.studentID] = student
        }

        var result: [UUID: Match] = [:]
        // Stored matches first; the ids they hold are taken.
        var taken: Set<String> = []
        var byName: [Child] = []
        for child in children {
            if let stored = child.parentLockerID?.trimmingCharacters(in: .whitespaces), !stored.isEmpty {
                if people[stored] != nil {
                    result[child.id] = .matched(studentID: stored, byName: false)
                    taken.insert(stored)
                } else {
                    result[child.id] = .unmatched
                }
            } else {
                byName.append(child)
            }
        }

        let open = people.values.filter { !taken.contains($0.studentID) }
        var fits: [UUID: [String]] = [:]
        var fitBy: [String: Int] = [:]
        for child in byName {
            let ids = open.filter { namesFit(child, $0) }.map(\.studentID).sorted()
            fits[child.id] = ids
            for id in ids { fitBy[id, default: 0] += 1 }
        }
        for child in byName {
            let ids = fits[child.id] ?? []
            if ids.isEmpty {
                result[child.id] = .unmatched
            } else if ids.count == 1, let only = ids.first, fitBy[only] == 1 {
                result[child.id] = .matched(studentID: only, byName: true)
            } else {
                result[child.id] = .ambiguous(ids)
            }
        }
        return result
    }

    /// Whether a notebook child and a ParentLocker child have the same name:
    /// the same last name, and the first name or nickname matching
    /// ParentLocker's first or alternate name (or its alternate name being the
    /// whole name). Case, accents and extra spaces don't count.
    static func namesFit(_ child: Child, _ student: ParentLockerRosterStudent) -> Bool {
        let last = normalizedName(child.lastName)
        guard !last.isEmpty, last == normalizedName(student.lastName) else { return false }
        let ours = Set([child.firstName, child.nickname ?? ""].map(normalizedName)).subtracting([""])
        let alternate = normalizedName(student.alternateName)
        let theirs = firstNames(student.firstName).union([alternate]).subtracting([""])
        if !ours.isDisjoint(with: theirs) { return true }
        return ours.contains { "\($0) \(last)" == alternate }
    }

    /// ParentLocker's first name as the names it stands for. The school writes
    /// a second name in brackets ("Toba (Aliza)", checked on the real roster
    /// 2026-10-12), so the whole name, each part and the name without the
    /// bracketed part all count.
    static func firstNames(_ name: String) -> Set<String> {
        let pieces = name.split(omittingEmptySubsequences: false) { $0 == "(" || $0 == ")" }.map(String.init)
        let outside = pieces.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element).joined(separator: " ")
        return Set(([name, outside] + pieces).map(normalizedName)).subtracting([""])
    }

    /// A name as matching reads it: lowercased, without accents, single-spaced.
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
