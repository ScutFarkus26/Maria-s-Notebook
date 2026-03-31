import Foundation
import CoreData
import SwiftData
import OSLog

/// Service for managing work assignments in project sessions
@MainActor
struct SessionWorkAssignmentService {
    private static let logger = Logger.work

    let context: NSManagedObjectContext

    // MARK: - Core Data Init

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    init(context: ModelContext) {
        self.context = AppBootstrapping.getSharedCoreDataStack().viewContext
    }

    // MARK: - Uniform Mode

    /// Creates a work item assigned to all project members (uniform mode)
    @discardableResult
    func createUniformWork(
        session: ProjectSession,
        memberStudentIDs: [String],
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
        work.studentID = memberStudentIDs.first ?? ""
        work.lessonID = lessonID.uuidString
        work.sourceContextType = .projectSession
        work.sourceContextID = session.id.uuidString

        // Create participants for all members
        for idString in memberStudentIDs {
            guard let uuid = UUID(uuidString: idString) else { continue }
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = uuid.uuidString
            participant.work = work
        }

        if !instructions.trimmed().isEmpty {
            work.setLegacyNoteText(instructions, in: context)
        }
        return work
    }

    // MARK: - Choice Mode

    /// Creates an offered work (no participants yet) for choice mode
    @discardableResult
    func createOfferedWork(
        session: ProjectSession,
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
        work.studentID = ""  // Empty - offered to group
        work.lessonID = lessonID.uuidString
        work.sourceContextType = .projectSession
        work.sourceContextID = session.id.uuidString

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
        if (work.studentID ?? "").isEmpty {
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
    func worksForSession(_ session: ProjectSession) -> [CDWorkModel] {
        let sessionID = session.id.uuidString
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "sourceContextID == %@", sessionID)
        return context.safeFetch(request)
    }

    /// Gets offered (unselected) works for a session
    func offeredWorksForSession(_ session: ProjectSession) -> [CDWorkModel] {
        worksForSession(session).filter(\.isOffered)
    }

    /// Gets works selected by a specific student in a session
    func worksSelectedByStudent(_ studentID: String, in session: ProjectSession) -> [CDWorkModel] {
        worksForSession(session).filter { work in
            let participants = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
            return participants.contains { $0.studentID == studentID }
        }
    }

    /// Checks selection status for a student in a session
    func selectionStatus(for studentID: String, in session: ProjectSession, works: [CDWorkModel]) -> SelectionStatus {
        let studentWorks = works.filter { work in
            let participants = (work.participants as? Set<CDWorkParticipantEntity>) ?? []
            return participants.contains { $0.studentID == studentID }
        }
        let count = studentWorks.count
        let min = session.minSelections
        let max = session.maxSelections

        if count < min {
            return .needsMore(selected: count, minimum: min)
        } else if max > 0 && count >= max {
            return .complete(selected: count)
        } else {
            return .inProgress(selected: count, minimum: min, maximum: max)
        }
    }

    // MARK: - Deprecated SwiftData Adapters

    /// Records a student's selection for an offered work (SwiftData WorkModel)
    @available(*, deprecated, message: "Use CDWorkModel overload")
    func recordSelection(work: WorkModel, studentID: UUID) {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", work.id as CVarArg)
        guard let cdWork = context.safeFetch(request).first else { return }
        recordSelection(work: cdWork, studentID: studentID)
    }

    /// Removes a student's selection (SwiftData WorkModel)
    @available(*, deprecated, message: "Use CDWorkModel overload")
    func removeSelection(work: WorkModel, studentID: UUID) {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", work.id as CVarArg)
        guard let cdWork = context.safeFetch(request).first else { return }
        removeSelection(work: cdWork, studentID: studentID)
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
        lesson.subject = "Projects"
        lesson.group = "Project"
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
