import Foundation
import CoreData
import OSLog

/// Service for managing work assignments in project sessions
struct SessionWorkAssignmentService {
    let context: NSManagedObjectContext

    // MARK: - Choice Mode

    /// Creates an offered work (no participants yet) for choice mode
    @discardableResult
    func createOfferedWork(
        session: CDProjectSession,
        title: String,
        instructions: String,
        dueDate: Date?
    ) throws -> CDWorkModel {
        let lessonID = resolveGenericProjectLessonID()

        let work = CDWorkModel(context: context)
        work.id = UUID()
        work.title = title
        work.kind = .followUpAssignment
        work.createdAt = Date()
        work.status = .active
        work.assignedAt = Date()
        work.dueAt = dueDate
        work.studentID = ""  // Empty - offered to sequence
        work.lessonID = lessonID.uuidString
        work.sourceContextType = .projectSession
        work.sourceContextID = session.id?.uuidString ?? ""

        if !instructions.trimmed().isEmpty {
            work.setLegacyNoteText(instructions, in: context)
        }
        return work
    }

    /// Records a student's selection for an offered work
    func recordSelection(work: CDWorkModel, studentID: UUID) {
        let idString = studentID.uuidString

        // Check if already selected
        let participants = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
        if participants.contains(where: { $0.studentID == idString }) {
            return // Already selected
        }

        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = idString
        participant.work = work

        // Update studentID if this is the first selection
        if work.studentID.isEmpty {
            work.studentID = idString
        }
    }

    /// Removes a student's selection
    func removeSelection(work: CDWorkModel, studentID: UUID) {
        let idString = studentID.uuidString

        // Find and remove her participant rows (a sync can leave two)
        let participants = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
        for participant in participants where participant.studentID == idString {
            context.delete(participant)
        }

        // Update studentID if we removed the primary. A deleted participant
        // stays in `participants` until the context processes the delete, so
        // picking "the first remaining" could pick her again; the heir is chosen
        // without her, by the rule work removal uses.
        if work.studentID == idString {
            work.studentID = WorkDeletionService.heir(after: studentID, on: work)?.uuidString ?? ""
        }
    }

    // MARK: - Members

    /// The project's members who are still enrolled, in member-list order. The
    /// member list keeps every child ever added, so a child who left would
    /// otherwise get new check-in work.
    static func enrolledMemberIDs(of project: CDProject, in context: NSManagedObjectContext) -> [String] {
        let members = project.memberStudentIDsArray
        guard !members.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            CDStudent.enrolledPredicate,
            NSPredicate(format: "id IN %@", members.compactMap(UUID.init(uuidString:)))
        ])
        let enrolled = Set(context.safeFetch(request).compactMap(\.id))
        var seen = Set<UUID>()
        return members.filter { member in
            guard let id = UUID(uuidString: member) else { return false }
            return enrolled.contains(id) && seen.insert(id).inserted
        }
    }

    // MARK: - Private Helpers

    private func resolveGenericProjectLessonID() -> UUID {
        let name = "Project Work"
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "name == %@", name)
        let existing = context.safeFetch(request)
        if let first = existing.first, let firstID = first.id {
            return firstID
        }
        let lesson = CDLesson(context: context)
        lesson.id = UUID()
        lesson.name = name
        lesson.area = "Projects"
        lesson.sequence = "Project"
        return lesson.id!
    }
}
