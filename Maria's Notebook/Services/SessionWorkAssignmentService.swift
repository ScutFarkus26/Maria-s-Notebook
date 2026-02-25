import Foundation
import SwiftData
import OSLog

/// Service for managing work assignments in project sessions
@MainActor
struct SessionWorkAssignmentService {
    private static let logger = Logger.work

    let context: ModelContext

    // MARK: - Uniform Mode

    /// Creates a work item assigned to all project members (uniform mode)
    @discardableResult
    func createUniformWork(
        session: ProjectSession,
        memberStudentIDs: [String],
        title: String,
        instructions: String,
        dueDate: Date?
    ) throws -> WorkModel {
        let lessonID = resolveGenericProjectLessonID()

        let work = WorkModel(
            id: UUID(),
            title: title,
            kind: .followUpAssignment,
            notes: instructions,
            createdAt: Date(),
            status: .active,
            assignedAt: Date(),
            dueAt: dueDate,
            studentID: memberStudentIDs.first ?? "",
            lessonID: lessonID.uuidString,
            sourceContextType: .projectSession,
            sourceContextID: session.id.uuidString
        )

        // Create participants for all members
        work.participants = memberStudentIDs.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return WorkParticipantEntity(studentID: uuid, work: work)
        }

        context.insert(work)
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
    ) throws -> WorkModel {
        let lessonID = resolveGenericProjectLessonID()

        let work = WorkModel(
            id: UUID(),
            title: title,
            kind: .followUpAssignment,
            notes: instructions,
            createdAt: Date(),
            status: .active,
            assignedAt: Date(),
            dueAt: dueDate,
            studentID: "",  // Empty - offered to group
            lessonID: lessonID.uuidString,
            sourceContextType: .projectSession,
            sourceContextID: session.id.uuidString
        )

        // Empty participants - no selections yet
        work.participants = []

        context.insert(work)
        return work
    }

    /// Records a student's selection for an offered work
    func recordSelection(work: WorkModel, studentID: UUID) {
        let idString = studentID.uuidString

        // Check if already selected
        if (work.participants ?? []).contains(where: { $0.studentID == idString }) {
            return // Already selected
        }

        let participant = WorkParticipantEntity(studentID: studentID, work: work)
        work.participants = (work.participants ?? []) + [participant]

        // Update studentID if this is the first selection
        if work.studentID.isEmpty {
            work.studentID = idString
        }
    }

    /// Removes a student's selection
    func removeSelection(work: WorkModel, studentID: UUID) {
        let idString = studentID.uuidString

        // Find and remove the participant
        if let participants = work.participants,
           let idx = participants.firstIndex(where: { $0.studentID == idString }) {
            let participant = participants[idx]
            work.participants?.remove(at: idx)
            context.delete(participant)
        }

        // Update studentID if we removed the primary
        if work.studentID == idString {
            work.studentID = (work.participants ?? []).first?.studentID ?? ""
        }
    }

    // MARK: - Queries

    /// Gets all works for a session
    func worksForSession(_ session: ProjectSession) -> [WorkModel] {
        let sessionID = session.id.uuidString
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { $0.sourceContextID == sessionID }
        )
        return safeFetch(descriptor, context: "worksForSession")
    }

    /// Gets offered (unselected) works for a session
    func offeredWorksForSession(_ session: ProjectSession) -> [WorkModel] {
        worksForSession(session).filter { $0.isOffered }
    }

    /// Gets works selected by a specific student in a session
    func worksSelectedByStudent(_ studentID: String, in session: ProjectSession) -> [WorkModel] {
        worksForSession(session).filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
        }
    }

    /// Checks selection status for a student in a session
    func selectionStatus(for studentID: String, in session: ProjectSession, works: [WorkModel]) -> SelectionStatus {
        let studentWorks = works.filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
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

    // MARK: - Private Helpers

    private func resolveGenericProjectLessonID() -> UUID {
        let name = "Project Work"
        let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.name == name })
        let existing = safeFetch(fetch, context: "resolveGenericProjectLessonID")
        if let first = existing.first {
            return first.id
        }
        let lesson = Lesson(name: name, subject: "Projects", group: "Project")
        context.insert(lesson)
        return lesson.id
    }

    // MARK: - Helper Methods

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> [T] {
        do {
            return try self.context.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
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
