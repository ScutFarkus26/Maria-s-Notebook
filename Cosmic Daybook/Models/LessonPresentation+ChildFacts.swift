// LessonPresentation+ChildFacts.swift
// Needs practice, needs another presentation and unlocked by hand, one child
// at a time (domain logic review 2026-11-20, R24; Decision 15, schema 25).
//
// The three were facts about one child kept on the group's presentation
// record, so one child's "needs practice" held back the whole group. Each
// child's history row now carries her own value (nil when never set on it).
// The group record keeps "any child", which is what older builds read:
//
// - Reading her value: the group's false is everyone's false (an older build
//   that clears the flag clears it for all). Otherwise her row's own value,
//   and with none, the group's.
// - Writing: `set(_:to:for:)` with nil writes everyone (the group, and every
//   row's own value cleared so it reads the group). For some children it
//   writes their rows, first copying every other child's value onto hers so
//   she keeps it, then sets the group to "any child".
//
// A plan not yet given has no history rows, so its value is the group's.

import CoreData
import Foundation

nonisolated extension CDLessonAssignment {

    /// A fact the presentation holds for each child.
    enum ChildFact: CaseIterable, Sendable {
        case needsPractice
        case needsAnotherPresentation
        case manuallyUnblocked
    }

    /// The group record's value: "any child" since schema 25.
    func groupValue(_ fact: ChildFact) -> Bool {
        switch fact {
        case .needsPractice: needsPractice
        case .needsAnotherPresentation: needsAnotherPresentation
        case .manuallyUnblocked: manuallyUnblocked
        }
    }

    private func setGroupValue(_ value: Bool, _ fact: ChildFact) {
        guard groupValue(fact) != value else { return }
        switch fact {
        case .needsPractice: needsPractice = value
        case .needsAnotherPresentation: needsAnotherPresentation = value
        case .manuallyUnblocked: manuallyUnblocked = value
        }
        modifiedAt = Date()
    }

    /// Her value. Reads her history row only when the group says some child
    /// has it and more than one child is on the record, so the common case
    /// fetches nothing.
    func value(_ fact: ChildFact, for studentID: UUID) -> Bool {
        guard groupValue(fact) else { return false }
        guard resolvedStudentIDs.count > 1 else { return true }
        return historyRows()[studentID]?.ownValue(fact) ?? true
    }

    /// Sets the fact for `studentIDs`, or for everyone when nil. See the file header.
    func set(_ fact: ChildFact, to value: Bool, for studentIDs: Set<UUID>? = nil) {
        let rows = historyRows()
        let children = Array(Set(resolvedStudentIDs))
        guard let studentIDs, children.count > 1 else {
            for row in rows.values where row.ownValue(fact) != nil { row.setOwnValue(nil, fact) }
            setGroupValue(value, fact)
            return
        }
        let group = groupValue(fact)
        var anyChild = false
        for studentID in children {
            // What she reads now, kept unless she is one of the children set.
            let current = group && (rows[studentID]?.ownValue(fact) ?? true)
            let own = studentIDs.contains(studentID) ? value : current
            if let row = rows[studentID], row.ownValue(fact) != own { row.setOwnValue(own, fact) }
            anyChild = anyChild || own
        }
        setGroupValue(anyChild, fact)
    }

    /// The history rows this presentation made, by child.
    private func historyRows() -> [UUID: CDLessonPresentation] {
        guard let id, let context = managedObjectContext else { return [:] }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", id.uuidString)
        var byChild: [UUID: CDLessonPresentation] = [:]
        for row in context.safeFetch(request) where !row.isDeleted {
            guard let studentID = UUID(uuidString: row.studentID.trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }
            byChild[studentID] = row
        }
        return byChild
    }
}

nonisolated extension CDLessonPresentation {

    /// Her own value for `fact`; nil when it was never set on her row.
    func ownValue(_ fact: CDLessonAssignment.ChildFact) -> Bool? {
        switch fact {
        case .needsPractice: needsPractice?.boolValue
        case .needsAnotherPresentation: needsAnotherPresentation?.boolValue
        case .manuallyUnblocked: manuallyUnblocked?.boolValue
        }
    }

    func setOwnValue(_ value: Bool?, _ fact: CDLessonAssignment.ChildFact) {
        let number = value.map { NSNumber(value: $0) }
        switch fact {
        case .needsPractice: needsPractice = number
        case .needsAnotherPresentation: needsAnotherPresentation = number
        case .manuallyUnblocked: manuallyUnblocked = number
        }
    }
}
