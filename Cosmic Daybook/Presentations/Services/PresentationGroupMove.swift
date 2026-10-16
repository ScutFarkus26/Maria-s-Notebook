// PresentationGroupMove.swift
// Moving one child between the groups of a lesson: from one planned
// presentation of it to another, or out into a new one.
//
// A group is its own `CDLessonAssignment` for the lesson. A move takes the
// child's id off one roster and puts it on the other, and
// `PresentationRecordCleanup.moveStudents` carries her own records along (the
// year-plan entries promoted into the source point at the target, and notes
// about her alone go to the target). A group
// she leaves empty is folded into the one she joined before it is deleted,
// so its notes do not cascade away with it. Dragging a chip onto another
// group (`PillDropDelegate`) and the Ready backlog's chip menu both go
// through `apply`, so the two cannot drift.
//
// A new group copies only the lesson's own fields from the group it came
// out of — never its notes or presentation records. A mastery mark filed on
// the group she leaves stays standing on its own (`keepMasteryMarks`).
//
// Nothing here saves; the caller owns the save. `undo` takes a move back from
// its receipt: a group the move deleted is rebuilt with its own id and
// fields and gets its notes back, and a group the move made is folded away.

import CoreData
import Foundation

enum PresentationGroupMove {

    /// What one move did, enough to take it back.
    struct Receipt {
        let studentID: String
        let sourceID: UUID
        let targetID: UUID
        /// The move made the target ("Move to a New Group").
        let createdTarget: Bool
        /// The source as it stood before the move emptied and deleted it.
        let deletedSource: DeletedGroup?
    }

    /// A group the move deleted: every stored attribute, and the notes it
    /// handed to the target.
    struct DeletedGroup {
        let attributes: [String: Any]
        let notes: [CDNote]
    }

    // MARK: - Moves

    /// Moves `studentID` from `source` to another group of the same lesson.
    /// Nil, changing nothing, when either group is given, they are different
    /// lessons, the child isn't on `source`, or is already on `target`.
    static func move(
        _ studentID: UUID,
        from source: CDLessonAssignment,
        to target: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) -> Receipt? {
        let id = studentID.uuidString
        guard let sourceID = source.id, let targetID = target.id, sourceID != targetID,
              !source.isGiven, !target.isGiven,
              source.resolvedLessonID == target.resolvedLessonID,
              source.studentIDs.contains(id), !target.studentIDs.contains(id) else { return nil }
        let willEmpty = source.studentIDs.allSatisfy { $0 == id }
        let snapshot = willEmpty ? deletedGroup(source) : nil
        let emptied = apply(id, from: source, to: target, in: context)
        return Receipt(
            studentID: id, sourceID: sourceID, targetID: targetID,
            createdTarget: false, deletedSource: emptied ? snapshot : nil
        )
    }

    /// Moves `studentID` out of `source` into a new planned group of the same
    /// lesson. Nil when she is the group's only child (a new group would just
    /// be this one again), the group is given, or she isn't on it.
    static func moveToNewGroup(
        _ studentID: UUID,
        from source: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) -> Receipt? {
        let id = studentID.uuidString
        guard let sourceID = source.id, !source.isGiven,
              source.studentIDs.contains(id), source.studentIDs.count > 1,
              let lessonID = UUID(uuidString: source.lessonID) else { return nil }
        let group = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [], context: context)
        copyLessonFields(from: source, to: group)
        guard let targetID = group.id else { return nil }
        apply(id, from: source, to: group, in: context)
        return Receipt(
            studentID: id, sourceID: sourceID, targetID: targetID,
            createdTarget: true, deletedSource: nil
        )
    }

    /// Moves one child from `source` to `target`; her year-plan entries and
    /// notes about her alone follow her. A group she leaves empty is folded into the target (its
    /// notes would cascade away with it) and deleted. Returns whether it was.
    @discardableResult
    static func apply(
        _ studentID: String,
        from source: CDLessonAssignment,
        to target: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) -> Bool {
        if !target.studentIDs.contains(studentID) {
            target.studentIDs.append(studentID)
        }
        source.studentIDs.removeAll { $0 == studentID }
        for moved in [source, target] {
            moved.updateDenormalizedKeys()
            moved.modifiedAt = Date()
        }
        // Both cleanups delete the source's history rows; a mastery or
        // proficiency mark filed on one is kept as a mark of its own first,
        // as Remove Plan does, so neither the move nor its Undo loses it.
        ChecklistRosterRemoval.keepMasteryMarks(on: source, studentIDs: [studentID], in: context)
        PresentationRecordCleanup.moveStudents([studentID], from: source, to: target, in: context)
        guard source.studentIDs.isEmpty else { return false }
        ChecklistRosterRemoval.keepMasteryMarks(on: source, studentIDs: nil, in: context)
        PresentationRecordCleanup.prepareToMerge(source, into: target, in: context)
        context.delete(source)
        return true
    }

    // MARK: - Undo

    /// Takes `receipt`'s move back. False, changing nothing, when the child is
    /// no longer on the group she was moved to, or either group has since
    /// been given or is gone.
    static func undo(_ receipt: Receipt, in context: NSManagedObjectContext) -> Bool {
        guard let target = context.object(CDLessonAssignment.self, id: receipt.targetID),
              !target.isDeleted, !target.isGiven,
              target.studentIDs.contains(receipt.studentID) else { return false }
        let source: CDLessonAssignment
        if let existing = context.object(CDLessonAssignment.self, id: receipt.sourceID), !existing.isDeleted {
            guard !existing.isGiven else { return false }
            source = existing
        } else if let deleted = receipt.deletedSource {
            source = CDLessonAssignment(context: context)
            source.setValuesForKeys(deleted.attributes)
            for note in deleted.notes where !note.isDeleted && note.lessonAssignment == target {
                note.lessonAssignment = source
            }
        } else {
            return false
        }
        // A group the move made is left empty here, so `apply` folds it back
        // into the source and deletes it.
        apply(receipt.studentID, from: target, to: source, in: context)
        return true
    }

    // MARK: - Pieces

    /// The fields that belong to the lesson rather than to one sitting of it.
    static func copyLessonFields(from source: CDLessonAssignment, to group: CDLessonAssignment) {
        group.lessonTitleSnapshot = source.lessonTitleSnapshot
        group.lessonSectionSnapshot = source.lessonSectionSnapshot
        group.trackID = source.trackID
        group.trackStepID = source.trackStepID
        // Unlock Lesson is the guide's word about the lesson; without it a
        // child moved out of an unlocked group would drop back to Brewing.
        group.manuallyUnblocked = source.manuallyUnblocked
    }

    private static func deletedGroup(_ group: CDLessonAssignment) -> DeletedGroup {
        let keys = Array(group.entity.attributesByName.keys)
        let notes = ((group.unifiedNotes as? Set<CDNote>) ?? []).filter { !$0.isDeleted }
        return DeletedGroup(attributes: group.dictionaryWithValues(forKeys: keys), notes: Array(notes))
    }
}
