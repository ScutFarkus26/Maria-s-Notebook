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
                workType: .practice,
                studentLessonID: work.studentLessonID,
                notes: work.notes,
                createdAt: work.createdAt,
                completedAt: Date()
            )
            completedCopy.participants = completedIDs.map { WorkParticipantEntity(studentID: $0, completedAt: Date(), work: completedCopy) }
            context.insert(completedCopy)
        }

        // Retain only remaining participants and clear completion on them
        work.participants.removeAll { !remaining.contains($0.studentID) }
        for i in work.participants.indices { work.participants[i].completedAt = nil }
        work.completedAt = nil
        try? context.save()
    }
}
