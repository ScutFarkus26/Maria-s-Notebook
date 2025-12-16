import Foundation
import SwiftData

struct LifecycleService {
    /// Record a Presentation (immutable) and create per-student WorkContract items.
    /// Idempotent by `legacyStudentLessonID` on Presentation and (presentationID, studentID) on WorkContract.
    static func recordPresentationAndExplodeWork(
        from studentLesson: StudentLesson,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (presentation: Presentation, work: [WorkContract]) {
        let t0 = Date()
        let legacyID = studentLesson.id.uuidString
        let lessonIDStr = studentLesson.lessonID.uuidString
        let studentIDStrs = studentLesson.studentIDs.map { $0.uuidString }

        // 1) Lookup existing Presentation by legacy link
        let existingPresentation: Presentation? = try fetchPresentation(byLegacyID: legacyID, context: modelContext)

        let presentation: Presentation
        var createdNewPresentation = false
        if let p = existingPresentation {
            presentation = p
        } else {
            // Create new Presentation
            let title = studentLesson.lesson?.name
            let subtitle = studentLesson.lesson?.subheading
            presentation = Presentation(
                id: UUID(),
                createdAt: Date(),
                presentedAt: presentedAt,
                lessonID: lessonIDStr,
                studentIDs: studentIDStrs,
                legacyStudentLessonID: legacyID,
                lessonTitleSnapshot: title,
                lessonSubtitleSnapshot: subtitle
            )
            modelContext.insert(presentation)
            createdNewPresentation = true
        }

        // 2) Ensure WorkContracts exist per student
        var workForPresentation: [WorkContract] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            if let existing = try fetchWorkContract(presentationID: presentation.id.uuidString, studentID: sid, context: modelContext) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                let wc = WorkContract(
                    id: UUID(),
                    createdAt: Date(),
                    studentID: sid,
                    lessonID: lessonIDStr,
                    presentationID: presentation.id.uuidString,
                    status: .active,
                    scheduledDate: nil,
                    completedAt: nil,
                    legacyStudentLessonID: legacyID
                )
                modelContext.insert(wc)
                workForPresentation.append(wc)
                createdCount += 1
            }
        }

        // 3) If there were existing contracts but we just created the presentation (e.g., backfill ordering), include them
        // Fetch all associated contracts to return a complete set
        let pid = presentation.id.uuidString
        let allForPresentation = try fetchAllWorkContracts(presentationID: pid, context: modelContext)

        #if DEBUG
        let dt = Date().timeIntervalSince(t0)
        print("[Lifecycle] recordPresentation: legacyID=\(legacyID.prefix(8))… foundExisting=\(!createdNewPresentation) students=\(studentIDStrs.count) time=\(String(format: "%.3f", dt))s created=\(createdCount) skipped=\(skippedCount)")
        #endif

        return (presentation, allForPresentation)
    }

    // MARK: - Fetch Helpers

    private static func fetchPresentation(byLegacyID legacyID: String, context: ModelContext) throws -> Presentation? {
        let descriptor = FetchDescriptor<Presentation>(predicate: #Predicate { $0.legacyStudentLessonID == legacyID })
        let arr = try context.fetch(descriptor)
        return arr.first
    }

    private static func fetchWorkContract(presentationID: String, studentID: String, context: ModelContext) throws -> WorkContract? {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { ($0.presentationID ?? "") == presentationID && $0.studentID == studentID })
        return try context.fetch(descriptor).first
    }

    private static func fetchAllWorkContracts(presentationID: String, context: ModelContext) throws -> [WorkContract] {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { ($0.presentationID ?? "") == presentationID })
        return try context.fetch(descriptor)
    }
}
