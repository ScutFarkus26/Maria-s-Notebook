//
//  StudentPickerModel.swift
//  Cosmic Daybook
//
//  Who a picker offers, in what order, and who it may not offer at all.
//
//  The search box, the level segments, the sort and the select-all button used
//  to live inside `StudentPickerPopover` as a chain of `filter`s over managed
//  objects, so none of it could be tested and each new rule made the view
//  longer. They are value-type functions here, and the views hand in candidates
//  read off Core Data once per appearance.
//
//  The rule this file adds is the one the guide asked for: a child who has left
//  the classroom is not silently missing from a lesson picker. She is listed,
//  disabled, with the reason beside her name — but only where forming a group
//  for a lesson is what the picker is for. Every other picker keeps today's
//  behaviour through the `.hidden` default.
//

import Foundation

// MARK: - Why a Child Cannot Be Picked

/// A child on file who has left the classroom. `nil` for an enrolled child —
/// the absence of a block is what makes a row selectable.
nonisolated enum StudentEnrollmentBlock: Equatable, Sendable {
    case withdrawn(on: Date?)
    case transferred(on: Date?)

    static func forStatus(
        _ status: CDStudent.EnrollmentStatus, departedOn: Date?
    ) -> StudentEnrollmentBlock? {
        switch status {
        case .enrolled: return nil
        case .withdrawn: return .withdrawn(on: departedOn)
        case .transferred: return .transferred(on: departedOn)
        }
    }

    /// The day she left, when the record has one.
    var departedOn: Date? {
        switch self {
        case let .withdrawn(day), let .transferred(day): return day
        }
    }

    /// The word the notebook uses for her status, lower case for mid-sentence use.
    var statusWord: String {
        switch self {
        case .withdrawn: return "withdrawn"
        case .transferred: return "transferred"
        }
    }

    /// `"Withdrawn Jun 12, 2026"` — the caption under a blocked picker row,
    /// or just `"Withdrawn"` when no departure day was recorded.
    var shortReason: String {
        let title = statusWord.prefix(1).uppercased() + statusWord.dropFirst()
        guard let day = departedOn else { return title }
        return "\(title) \(DateFormatters.mediumDate.string(from: day))"
    }

    /// `"Naomi Levin is withdrawn (departed 2026-06-12) and cannot be scheduled
    /// for a presentation."` — one child, for a tool refusal.
    ///
    /// The day arrives already formatted: the MCP tools print ISO days in the
    /// school's own time zone through `MCPNotebookTools.dayString`, and this
    /// type stays free of date formatting policy it cannot see.
    func refusal(name: String, action: String, departedDay: String?) -> String {
        let departure = departedDay.map { " (departed \($0))" } ?? ""
        return "\(name) is \(statusWord)\(departure) and cannot be \(action)."
    }

    /// `"Naomi Levin (withdrawn, departed 2026-06-12)"` — one entry in the
    /// list form a refusal uses when more than one child is named.
    func listEntry(name: String, departedDay: String?) -> String {
        let departure = departedDay.map { ", departed \($0)" } ?? ""
        return "\(name) (\(statusWord)\(departure))"
    }
}

// MARK: - A Child a Picker Can Offer

/// One child, read off the store once, with everything a picker row needs.
nonisolated struct StudentPickerCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let birthday: Date?
    let level: CDStudent.Level
    let status: CDStudent.EnrollmentStatus
    let departedOn: Date?

    /// "Maya S" — the canonical short name, never a second copy of the rule.
    var displayName: String {
        StudentFormatter.displayName(firstName: firstName, lastName: lastName)
    }

    var enrollmentBlock: StudentEnrollmentBlock? {
        StudentEnrollmentBlock.forStatus(status, departedOn: departedOn)
    }
}

/// A candidate placed in a list: what the record holds for her on the picker's
/// lesson, and whether she may be picked at all.
nonisolated struct StudentPickerRow: Identifiable, Equatable, Sendable {
    let candidate: StudentPickerCandidate
    /// What the record says about her and the picker's lesson. `nil` when the
    /// picker has no lesson, or when nothing is on record.
    let record: PresentationRecordIndex.Given?
    let block: StudentEnrollmentBlock?

    var id: UUID { candidate.id }
    var isSelectable: Bool { block == nil }
}

// MARK: - The Rules

nonisolated enum StudentPickerModel {

    /// What a picker does with a child who has left the classroom. Lesson
    /// pickers show her disabled with the reason; every other picker keeps
    /// today's behaviour and drops her.
    enum FormerStudents: Equatable, Sendable {
        case hidden
        case shownBlocked
    }

    enum Sort: String, Equatable, Sendable {
        case name
        case age
    }

    enum LevelScope: Equatable, Sendable {
        case all
        case level(CDStudent.Level)
    }

    /// What a picker is currently showing: its search box, its level segments,
    /// its sort, and its policy on children who have left.
    struct Query: Equatable, Sendable {
        var search: String = ""
        var scope: LevelScope = .all
        var sort: Sort = .name
        var formerStudents: FormerStudents = .hidden
    }

    /// The rows a picker shows: searched, scoped to a level, sorted, and
    /// captioned from the record.
    static func rows(
        candidates: [StudentPickerCandidate],
        query: Query,
        records: [UUID: PresentationRecordIndex.Given]
    ) -> [StudentPickerRow] {
        let search = query.search.normalizedForComparison()
        let kept = candidates.filter { candidate in
            matches(candidate, query: search) && inScope(candidate, scope: query.scope)
                && keeps(candidate, formerStudents: query.formerStudents)
        }
        return sorted(kept, by: query.sort).map { candidate in
            StudentPickerRow(
                candidate: candidate,
                record: records[candidate.id],
                block: candidate.enrollmentBlock
            )
        }
    }

    /// The ids the select-all control may touch — never a blocked child.
    static func selectableIDs(_ rows: [StudentPickerRow]) -> [UUID] {
        rows.filter(\.isSelectable).map(\.id)
    }

    /// Tapping a row. A blocked child can never be added; one already in the
    /// selection can always be taken out, which is how a roster gets cleaned
    /// up after a departure.
    static func toggling(
        _ id: UUID, in selection: Set<UUID>, rows: [StudentPickerRow]
    ) -> Set<UUID> {
        var next = selection
        if next.contains(id) {
            next.remove(id)
            return next
        }
        guard rows.first(where: { $0.id == id })?.isSelectable == true else { return next }
        next.insert(id)
        return next
    }

    /// Select-all over what is on screen, or deselect it when it is all there.
    static func selectAll(
        _ rows: [StudentPickerRow], in selection: Set<UUID>
    ) -> Set<UUID> {
        let ids = selectableIDs(rows)
        guard !ids.isEmpty else { return selection }
        var next = selection
        if ids.allSatisfy(selection.contains) {
            next.subtract(ids)
        } else {
            next.formUnion(ids)
        }
        return next
    }

    // MARK: - Pieces

    private static func matches(_ candidate: StudentPickerCandidate, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let first = candidate.firstName.lowercased()
        let last = candidate.lastName.lowercased()
        if first.contains(query) || last.contains(query) { return true }
        return "\(first) \(last)".contains(query)
    }

    private static func inScope(_ candidate: StudentPickerCandidate, scope: LevelScope) -> Bool {
        switch scope {
        case .all: return true
        case let .level(level): return candidate.level == level
        }
    }

    private static func keeps(
        _ candidate: StudentPickerCandidate, formerStudents: FormerStudents
    ) -> Bool {
        switch formerStudents {
        case .hidden: return candidate.enrollmentBlock == nil
        case .shownBlocked: return true
        }
    }

    /// Age runs oldest first, matching the student columns on the checklist
    /// these pickers filter. Children with no birthday on file sink to the
    /// bottom rather than posing as newborns.
    private static func sorted(
        _ candidates: [StudentPickerCandidate], by sort: Sort
    ) -> [StudentPickerCandidate] {
        switch sort {
        case .name:
            return candidates.sorted(by: byName)
        case .age:
            return candidates.sorted { lhs, rhs in
                switch (lhs.birthday, rhs.birthday) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return byName(lhs, rhs)
                case (nil, nil): return byName(lhs, rhs)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }

    /// The same order as `StudentSortComparator.byFirstName`, on values.
    private static func byName(
        _ lhs: StudentPickerCandidate, _ rhs: StudentPickerCandidate
    ) -> Bool {
        let first = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
        if first == .orderedSame {
            return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
        }
        return first == .orderedAscending
    }
}
