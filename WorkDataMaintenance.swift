import Foundation
import SwiftData

enum WorkDataMaintenance {
    /// Backfill participants for any WorkModel that is missing them.
    /// If a WorkModel links to a StudentLesson, mirror its studentIDs into participants.
    /// Safe to call multiple times; it is idempotent.
    static func backfillParticipantsIfNeeded(using context: ModelContext) {
        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            var changed = false
            for w in works where w.participants.isEmpty {
                if let slID = w.studentLessonID {
                    let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == slID })
                    if let sl = try? context.fetch(descriptor).first {
                        let newParticipants = sl.studentIDs.map { sid in
                            WorkParticipantEntity(studentID: sid, completedAt: nil, work: w)
                        }
                        if !newParticipants.isEmpty {
                            w.participants = newParticipants
                            changed = true
                        }
                    }
                }
            }
            if changed { try context.save() }
        } catch {
            // Non-fatal; maintenance best-effort
        }
    }
}
