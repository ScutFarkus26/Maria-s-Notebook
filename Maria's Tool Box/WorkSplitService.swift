import SwiftData
import Foundation

enum WorkSplitService {
    static func splitPracticeWork(_ work: WorkModel, completedIDs: Set<UUID>, context: ModelContext) {
        // Only applicable to practice work
        guard work.workType == .practice else { return }
        let allIDs = Set((work.participants ?? []).map { $0.studentID })
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
            completedCopy.participants = (completedCopy.participants ?? []) + completedIDs.map { WorkParticipantEntity(studentID: $0, completedAt: Date(), work: completedCopy) }
            context.insert(completedCopy)
        }

        // Retain only remaining participants and clear completion on them
        let current = work.participants ?? []
        let kept = current.filter { remaining.contains($0.studentID) }
        for p in kept { p.completedAt = nil }
        work.participants = kept
        work.completedAt = nil
        try? context.save()
    }
}
