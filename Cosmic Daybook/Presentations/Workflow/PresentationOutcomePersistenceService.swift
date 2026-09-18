import CoreData
import Foundation

/// Persists the guide's observations from the post-presentation workflow.
///
/// Presentation observations must stay attached to the exact presentation the
/// guide is closing. This service deliberately does not guess which repeated
/// presentation was meant when an ID is missing.
struct PresentationOutcomePersistenceService {
    enum PersistenceError: LocalizedError {
        case missingPresentationID
        case presentationNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .missingPresentationID:
                return "This presentation does not have a saved identity yet. Close this window and try again."
            case .presentationNotFound:
                return "The presentation could not be found. Nothing was saved so your observations are not attached to the wrong lesson."
            }
        }
    }

    /// Saves one shared observation plus any student-specific observations.
    /// Blank text is ignored, and retrying the same save does not duplicate notes.
    @discardableResult
    static func persistObservations(
        groupObservation: String,
        studentObservations: [UUID: String],
        studentIDs: [UUID],
        presentationID: UUID?,
        context: NSManagedObjectContext
    ) throws -> [CDNote] {
        guard let presentationID else {
            throw PersistenceError.missingPresentationID
        }

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", presentationID as CVarArg)
        request.fetchLimit = 1
        guard let assignment = try context.fetch(request).first else {
            throw PersistenceError.presentationNotFound(presentationID)
        }

        let assignmentStudentIDs = Set(assignment.studentUUIDs)
        let orderedStudentIDs = uniqueStudentIDs(studentIDs)
            .filter { assignmentStudentIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
        var persisted: [CDNote] = []

        let sharedText = groupObservation.trimmed()
        if !sharedText.isEmpty, !orderedStudentIDs.isEmpty {
            let sharedScope: NoteScope = orderedStudentIDs.count == 1
                ? .student(orderedStudentIDs[0])
                : .students(orderedStudentIDs)
            if let note = makeNoteIfNeeded(
                body: sharedText,
                scope: sharedScope,
                assignment: assignment,
                context: context
            ) {
                persisted.append(note)
            }
        }

        for studentID in orderedStudentIDs {
            let text = studentObservations[studentID]?.trimmed() ?? ""
            guard !text.isEmpty else { continue }
            if let note = makeNoteIfNeeded(
                body: text,
                scope: .student(studentID),
                assignment: assignment,
                context: context
            ) {
                persisted.append(note)
            }
        }

        return persisted
    }

    private static func makeNoteIfNeeded(
        body: String,
        scope: NoteScope,
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) -> CDNote? {
        let existing = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        guard !existing.contains(where: { note in
            note.body.trimmed() == body && scopesMatch(note.scope, scope)
        }) else {
            return nil
        }

        let note = CDNote(context: context)
        note.body = body
        note.scope = scope
        note.lessonID = assignment.lessonID
        note.lessonAssignment = assignment
        note.syncStudentLinks(in: context)
        return note
    }

    private static func uniqueStudentIDs(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private static func scopesMatch(_ lhs: NoteScope, _ rhs: NoteScope) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all):
            return true
        case let (.student(lhsID), .student(rhsID)):
            return lhsID == rhsID
        case let (.students(lhsIDs), .students(rhsIDs)):
            return Set(lhsIDs) == Set(rhsIDs)
        default:
            return false
        }
    }
}
