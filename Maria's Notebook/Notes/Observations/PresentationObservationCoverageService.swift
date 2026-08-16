import CoreData
import Foundation

/// Finds presentations that have no factual observation attached. This is a
/// deterministic database check, not an AI judgment.
@MainActor
enum PresentationObservationCoverageService {
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
               studentIDs.isDisjoint(with: Set(assignment.studentUUIDs)) {
                return nil
            }
            let linkedNotes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
            guard !linkedNotes.contains(where: { !$0.body.trimmed().isEmpty || $0.imagePath?.isEmpty == false }) else {
                return nil
            }

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
