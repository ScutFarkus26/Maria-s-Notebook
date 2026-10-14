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
//  The present-a-lesson picker (2026-10-13) lists only the class as it is now,
//  plus anyone already on the presentation who has since left, and orders the
//  list for the job: the children already picked, then the ones ready for the
//  lesson, then everyone else, each run A–Z (`Arrangement.selectedThenReady`).
//  A level with no enrolled child is not offered as a segment in any picker.
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

    /// Where she sits in a picker arranged Selected → Ready → Everyone Else;
    /// `nil` in a picker ordered by its sort menu.
    var placement: StudentPickerModel.Placement?

    var id: UUID { candidate.id }
    var isSelectable: Bool { block == nil }
    /// Ready for the picker's lesson by the ready queue's rules.
    var isReady: Bool { placement == .ready }
}

// MARK: - The Rules

nonisolated enum StudentPickerModel {

    /// What a picker does with a child who has left the classroom. Lesson
    /// pickers show her disabled with the reason; every other picker keeps
    /// today's behaviour and drops her.
    enum FormerStudents: Equatable, Sendable {
        case hidden
        case shownBlocked
        /// Shown, blocked, only when she was already picked as the picker
        /// opened (`Query.pinned`), so she can be taken off; otherwise dropped.
        case shownIfSelected
    }

    /// How a picker orders its rows.
    enum Arrangement: Equatable, Sendable {
        /// By the remembered Name / Age sort menu.
        case sortMenu
        /// Selected, then Ready, then everyone else, each A–Z by name. The
        /// sort menu is not offered.
        case selectedThenReady
    }

    /// The runs a `.selectedThenReady` picker shows, in order.
    enum Placement: Int, CaseIterable, Comparable, Sendable {
        case selected
        case ready
        case everyoneElse

        var title: String {
            switch self {
            case .selected: return "Selected"
            case .ready: return "Ready"
            case .everyoneElse: return "Everyone Else"
            }
        }

        static func < (lhs: Placement, rhs: Placement) -> Bool { lhs.rawValue < rhs.rawValue }
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
        var arrangement: Arrangement = .sortMenu
        /// Who was picked when the picker opened. The Selected run is read
        /// from this, not the live selection, so a tap never moves the row
        /// under the guide's finger.
        var pinned: Set<UUID> = []
        /// Who is ready for the picker's lesson.
        var ready: Set<UUID> = []
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
                && keeps(candidate, query: query)
        }
        switch query.arrangement {
        case .sortMenu:
            return sorted(kept, by: query.sort).map { candidate in
                StudentPickerRow(
                    candidate: candidate,
                    record: records[candidate.id],
                    block: candidate.enrollmentBlock
                )
            }
        case .selectedThenReady:
            return kept
                .map { candidate in
                    StudentPickerRow(
                        candidate: candidate,
                        record: records[candidate.id],
                        block: candidate.enrollmentBlock,
                        placement: placement(of: candidate, query: query)
                    )
                }
                .sorted { lhs, rhs in
                    let left = lhs.placement ?? .everyoneElse
                    let right = rhs.placement ?? .everyoneElse
                    if left != right { return left < right }
                    return byDisplayName(lhs.candidate, rhs.candidate)
                }
        }
    }

    /// Rows already in order, split into their runs; empty runs are left out.
    /// A `.sortMenu` picker's rows come back as one untitled run.
    static func sections(
        _ rows: [StudentPickerRow]
    ) -> [(placement: Placement?, rows: [StudentPickerRow])] {
        var result: [(placement: Placement?, rows: [StudentPickerRow])] = []
        for row in rows {
            if let last = result.indices.last, result[last].placement == row.placement {
                result[last].rows.append(row)
            } else {
                result.append((row.placement, [row]))
            }
        }
        return result
    }

    /// The levels a picker offers as segments: only those with an enrolled
    /// child among its candidates, in the notebook's level order. A child who
    /// has left never keeps a level on offer.
    static func offeredLevels(_ candidates: [StudentPickerCandidate]) -> [CDStudent.Level] {
        let present = Set(candidates.filter { $0.enrollmentBlock == nil }.map(\.level))
        return CDStudent.Level.allCases.filter(present.contains)
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

    private static func keeps(_ candidate: StudentPickerCandidate, query: Query) -> Bool {
        switch query.formerStudents {
        case .hidden: return candidate.enrollmentBlock == nil
        case .shownBlocked: return true
        case .shownIfSelected:
            return candidate.enrollmentBlock == nil || query.pinned.contains(candidate.id)
        }
    }

    /// Selected wins over Ready: a child already on the lesson is not waiting
    /// for it. A child who has left is never Ready.
    private static func placement(of candidate: StudentPickerCandidate, query: Query) -> Placement {
        if query.pinned.contains(candidate.id) { return .selected }
        if candidate.enrollmentBlock == nil, query.ready.contains(candidate.id) { return .ready }
        return .everyoneElse
    }

    /// A–Z by the name the row shows ("Maya S"), then by full name, so two
    /// children with one short name keep an order.
    private static func byDisplayName(
        _ lhs: StudentPickerCandidate, _ rhs: StudentPickerCandidate
    ) -> Bool {
        let shown = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if shown != .orderedSame { return shown == .orderedAscending }
        return byName(lhs, rhs)
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
