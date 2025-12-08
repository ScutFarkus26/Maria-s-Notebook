import Foundation
import SwiftData

@MainActor
struct WorkRepository {
    let context: ModelContext

    // MARK: - Fetch
    func fetchWork(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Create
    @discardableResult
    func createWork(title: String,
                    studentIDs: [UUID],
                    type: WorkModel.WorkType,
                    studentLessonID: UUID?,
                    notes: String) throws -> WorkModel {
        let work = WorkModel(
            id: UUID(),
            title: title,
            workType: type,
            studentLessonID: studentLessonID,
            notes: notes,
            createdAt: Date()
        )
        work.participants = studentIDs.map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: work) }
        context.insert(work)
        try context.save()
        return work
    }

    // MARK: - Toggle Completion (per student)
    func toggleCompletion(workID: UUID, studentID: UUID) throws {
        guard let work = fetchWork(id: workID) else { return }
        if work.isStudentCompleted(studentID) {
            work.markStudent(studentID, completedAt: nil)
        } else {
            work.markStudent(studentID, completedAt: Date())
        }
        try context.save()
    }

    // MARK: - Delete
    func deleteWork(id: UUID) throws {
        guard let work = fetchWork(id: id) else { return }
        // Resolve attributes that UI might still touch briefly
        _ = work.title
        _ = work.notes
        _ = work.createdAt
        _ = work.completedAt
        _ = work.workType
        _ = work.studentLessonID
        for p in work.participants { _ = p.studentID; _ = p.completedAt }
        for ci in work.checkIns { _ = ci.id; _ = ci.date; _ = ci.status; _ = ci.purpose; _ = ci.note }

        context.delete(work)
        try context.save()
    }
}

