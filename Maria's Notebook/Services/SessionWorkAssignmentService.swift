import Foundation
import CoreData
import OSLog

/// Service for managing work assignments in project sessions
@MainActor
struct SessionWorkAssignmentService {
    private static let logger = Logger.work

    let context: NSManagedObjectContext

    // Deprecated ModelContext init removed - no longer needed with Core Data.

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

        // Find and remove the participant
        let participants = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
        if let participant = participants.first(where: { $0.studentID == idString }) {
            context.delete(participant)
        }

        // Update studentID if we removed the primary
        if work.studentID == idString {
            let remaining = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
            work.studentID = remaining.first?.studentID ?? ""
        }
    }

    // MARK: - Queries

    /// Gets all works for a session
    func worksForSession(_ session: CDProjectSession) -> [CDWorkModel] {
        let sessionID = session.id?.uuidString ?? ""
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "sourceContextID == %@", sessionID)
        return context.safeFetch(request)
    }

    // Deprecated SwiftData adapter overloads removed - typealiases now point to CD types directly.

    // MARK: - Private Helpers

    private func resolveGenericProjectLessonID() -> UUID {
        let name = "CDProject Work"
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

// MARK: - Selection Status

/// Represents the selection status for a student in a choice-mode session
enum SelectionStatus: Equatable {
    case needsMore(selected: Int, minimum: Int)
    case inProgress(selected: Int, minimum: Int, maximum: Int)
    case complete(selected: Int)

    var isValid: Bool {
        switch self {
        case .needsMore: return false
        case .inProgress, .complete: return true
        }
    }

    var displayText: String {
        switch self {
        case .needsMore(let selected, let minimum):
            return "\(selected)/\(minimum) selected"
        case .inProgress(let selected, let minimum, let maximum):
            let maxText = maximum > 0 ? "/\(maximum)" : ""
            return "\(selected)\(maxText) selected (min \(minimum))"
        case .complete(let selected):
            return "\(selected) selected"
        }
    }
}
