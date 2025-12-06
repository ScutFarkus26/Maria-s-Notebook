import SwiftData
import Foundation

enum WorkSplitService {
    static func splitPracticeWork(_ work: WorkModel, completedIDs: Set<UUID>, context: ModelContext) {
        // Only applicable to practice work
        guard work.workType == .practice else { return }
        let allIDs = Set(work.participants.map { $0.studentID })
        let remaining = allIDs.subtracting(completedIDs)

        if !completedIDs.isEmpty {
            let completedCopy = WorkModel(
                id: UUID(),
                title: work.title,
                studentIDs: Array(completedIDs),
                workType: .practice,
                studentLessonID: work.studentLessonID,
                notes: work.notes,
                createdAt: work.createdAt,
                completedAt: Date()
            )
            completedCopy.participants = completedIDs.map { WorkParticipantEntity(studentID: $0, completedAt: Date(), work: completedCopy) }
            completedCopy.mirrorStudentIDsFromParticipants()
            context.insert(completedCopy)
        }

        work.studentIDs = Array(remaining)
        work.ensureParticipantsFromStudentIDs()
        work.mirrorStudentIDsFromParticipants()
        work.completedAt = nil
        try? context.save()
    }
}
