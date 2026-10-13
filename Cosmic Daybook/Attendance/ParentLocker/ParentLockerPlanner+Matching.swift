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
        /// The guide picked "Not matched" in Match Names (`notMatchedID`):
        /// never matched by name, never sent, and nothing to ask about.
        case leftOut
        /// The ParentLocker children who fit, when more than one does (or the
        /// one who does also fits another notebook child).
        case ambiguous([String])
    }

    /// The stored `parentLockerID` for "Not matched": the guide said this
    /// child has no ParentLocker child. No schema change: ParentLocker's own
    /// ids are numbers, so this can't be one of them.
    static let notMatchedID = "none"

    /// Whether a stored `parentLockerID` is "Not matched".
    static func isNotMatched(_ stored: String) -> Bool {
        stored.trimmingCharacters(in: .whitespaces).lowercased() == notMatchedID
    }

    /// The ParentLocker children matched to exactly one notebook child, and
    /// who. An id two children claim goes to neither: one child's mark must
    /// never land on another.
    static func childByStudentID(_ matches: [UUID: Match]) -> [String: UUID] {
        var result: [String: UUID] = [:]
        var claimedTwice: Set<String> = []
        for (childID, match) in matches {
            guard case .matched(let studentID, _) = match else { continue }
            if result.updateValue(childID, forKey: studentID) != nil { claimedTwice.insert(studentID) }
        }
        for studentID in claimedTwice { result[studentID] = nil }
        return result
    }

    /// Every child's match against the children on `rosters`.
    static func match(children: [Child], rosters: [ParentLockerRoster]) -> [UUID: Match] {
        var people: [String: ParentLockerRosterStudent] = [:]
        for student in rosters.flatMap(\.students) where people[student.studentID] == nil {
            people[student.studentID] = student
        }

        // Stored matches first; the ids they hold on the rosters are taken.
        var result = storedMatches(children: children, people: people)
        let byName = children.filter { result[$0.id] == nil }
        let taken = Set(children.compactMap { $0.parentLockerID?.trimmingCharacters(in: .whitespaces) })
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

    /// The match of each child with a stored `parentLockerID`. "Not matched"
    /// is left out. An id two children hold (picked twice, or a duplicated
    /// student) matches neither, and is still taken: no one gets it by name.
    private static func storedMatches(
        children: [Child], people: [String: ParentLockerRosterStudent]
    ) -> [UUID: Match] {
        var result: [UUID: Match] = [:]
        var stored: [UUID: String] = [:]
        var holders: [String: Int] = [:]
        for child in children {
            guard let id = child.parentLockerID?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { continue }
            if isNotMatched(id) {
                result[child.id] = .leftOut
            } else {
                stored[child.id] = id
                holders[id, default: 0] += 1
            }
        }
        for (childID, id) in stored {
            if people[id] == nil {
                result[childID] = .unmatched
            } else {
                result[childID] = holders[id] == 1 ? .matched(studentID: id, byName: false) : .ambiguous([id])
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

    // MARK: - What ParentLocker held

    /// What `rosters` hold for each matched child, by child.
    static func seen(matches: [UUID: Match], rosters: [ParentLockerRoster]) -> [UUID: ParentLockerSeen] {
        let childByStudent = childByStudentID(matches)
        var seen: [UUID: ParentLockerSeen] = [:]
        for roster in rosters {
            for student in roster.students {
                guard let childID = childByStudent[student.studentID] else { continue }
                seen[childID, default: ParentLockerSeen()].rows[roster.course.courseID] = student.seenRow
            }
        }
        return seen
    }

    /// The children among `imported` (changes synced in from another device)
    /// whose ParentLocker rows have changed since this device last saw them
    /// (`before`, taken when the change was noted): someone saved them since,
    /// most likely the device that made the change, maybe with a newer mark
    /// than the one that synced in here. They're left to that device. A child
    /// this device never saw counts as changed when ParentLocker holds a
    /// saved mark for them; with none, nothing newer can be overwritten.
    static func changedElsewhere(
        _ imported: Set<UUID>, before: [UUID: ParentLockerSeen], now: [UUID: ParentLockerSeen]
    ) -> Set<UUID> {
        imported.filter { child in
            // Not on the rosters: the plan reports them as unmatched.
            guard let current = now[child] else { return false }
            let seenRows = before[child]?.rows ?? [:]
            let classes = Set(seenRows.keys).intersection(current.rows.keys)
            guard !classes.isEmpty else { return current.holdsMark }
            return classes.contains { seenRows[$0] != current.rows[$0] }
        }
    }
}
