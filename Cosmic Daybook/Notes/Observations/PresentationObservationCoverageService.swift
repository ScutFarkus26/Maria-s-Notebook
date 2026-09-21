import CoreData
import Foundation

/// Finds presentations that have no factual observation attached. This is a
/// deterministic database check, not an AI judgment.
///
/// Observations link to a presentation as a whole; which child each one is
/// about is the note's scope. A group presentation is therefore covered
/// child by child: a note about Etty covers Etty, not Ora beside her.
enum PresentationObservationCoverageService {
    /// Whether `note` counts as an observation of `studentID` — it has
    /// content and its scope names her (or the whole class).
    static func observes(_ note: CDNote, _ studentID: UUID) -> Bool {
        let hasText: Bool = !note.body.trimmed().isEmpty
        let hasPhoto: Bool = note.imagePath?.isEmpty == false
        guard hasText || hasPhoto else { return false }
        return note.scope.applies(to: studentID)
    }

    /// The children on `assignment` with no linked observation about them.
    static func unobservedStudentIDs(on assignment: CDLessonAssignment) -> [UUID] {
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        return assignment.resolvedStudentIDs.filter { studentID in
            !notes.contains { observes($0, studentID) }
        }
    }

    static func missingObservationReferences(
        in context: NSManagedObjectContext,
        from startDate: Date,
        through endDate: Date,
        studentIDs: Set<UUID> = []
    ) -> [EvidenceReference] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "stateRaw == %@ AND presentedAt >= %@ AND presentedAt <= %@",
            LessonAssignmentState.presented.rawValue,
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)]

        return context.safeFetch(request).compactMap { assignment in
            guard let assignmentID = assignment.id else { return nil }
            if !studentIDs.isEmpty,
               studentIDs.isDisjoint(with: Set(assignment.resolvedStudentIDs)) {
                return nil
            }
            // Missing for the children asked about (or any child on it), not
            // for the presentation as a whole.
            let unobserved = Set(unobservedStudentIDs(on: assignment))
            let considered = studentIDs.isEmpty ? unobserved : unobserved.intersection(studentIDs)
            guard !considered.isEmpty else { return nil }

            let snapshotTitle = assignment.lessonTitleSnapshot?.trimmed() ?? ""
            let liveTitle = assignment.lesson?.name.trimmed() ?? ""
            let title = !snapshotTitle.isEmpty
                ? snapshotTitle
                : (!liveTitle.isEmpty ? liveTitle : "Lesson Presentation")
            return EvidenceReference(
                entityKind: .presentation,
                entityID: assignmentID,
                date: assignment.presentedAt,
                title: title,
                excerpt: "No observation is linked to this presentation."
            )
        }
    }
}
