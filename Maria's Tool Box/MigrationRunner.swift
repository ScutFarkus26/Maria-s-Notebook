import SwiftData
import Foundation

enum MigrationRunner {
    static func runIfNeeded(context: ModelContext) {
        let key = "MigrationRunner.v1.practiceFollowUpBackfill"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        defer { UserDefaults.standard.set(true, forKey: key) }

        let sls = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
        let works = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []

        // Build a map of works by studentLessonID for quick lookups
        let worksBySL: [UUID: [WorkModel]] = works.reduce(into: [:]) { dict, w in
            if let slID = w.studentLessonID { dict[slID, default: []].append(w) }
        }

        for sl in sls {
            let worksForSL = worksBySL[sl.id] ?? []

            // Backfill practice
            if sl.needsPractice {
                let hasPractice = worksForSL.contains { $0.workType == .practice }
                if !hasPractice {
                    let w = WorkModel(
                        id: UUID(),
                        title: "Practice: \(sl.lesson?.name ?? "Lesson")",
                        studentIDs: sl.studentIDs,
                        workType: .practice,
                        studentLessonID: sl.id,
                        notes: "",
                        createdAt: Date()
                    )
                    w.ensureParticipantsFromStudentIDs()
                    w.mirrorStudentIDsFromParticipants()
                    context.insert(w)
                }
            }

            // Backfill follow-up
            let trimmed = sl.followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let hasFollow = worksForSL.contains { $0.workType == .followUp && $0.notes == trimmed }
                if !hasFollow {
                    let w = WorkModel(
                        id: UUID(),
                        title: "Follow Up: \(sl.lesson?.name ?? "Lesson")",
                        studentIDs: sl.studentIDs,
                        workType: .followUp,
                        studentLessonID: sl.id,
                        notes: trimmed,
                        createdAt: Date()
                    )
                    w.ensureParticipantsFromStudentIDs()
                    w.mirrorStudentIDsFromParticipants()
                    context.insert(w)
                }
            }
        }
        try? context.save()
    }
}
