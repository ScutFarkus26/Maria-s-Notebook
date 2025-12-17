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
        let legacyID = studentLesson.id.uuidString
        let lessonIDStr = studentLesson.lessonID.uuidString
        let studentIDStrs = studentLesson.studentIDs.map { $0.uuidString }

        // 1) Lookup existing Presentation by legacy link
        let existingPresentation: Presentation? = try fetchPresentation(byLegacyID: legacyID, context: modelContext)

        let presentation: Presentation
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
        }

        // MIGRATION: Copy legacy notes from StudentLesson to Presentation (idempotent)
        // Build existing migration keys for this Presentation to keep this fast and idempotent.
        let presentationUUID = presentation.id
        let existingForPresentationFetch = FetchDescriptor<ScopedNote>(predicate: #Predicate<ScopedNote> { ($0.presentationID ?? "") == presentationUUID.uuidString && $0.migrationKey != nil })
        let existingForPresentation = try modelContext.fetch(existingForPresentationFetch)
        var existingKeys: Set<String> = Set(existingForPresentation.compactMap { $0.migrationKey })

        // A) Scoped notes attached to StudentLesson → Presentation
        for legacy in studentLesson.scopedNotes {
            let mk = "studentLessonScopedNote:\(studentLesson.id.uuidString):\(legacy.id.uuidString)"
            if existingKeys.contains(mk) {
                continue
            }
            let newNote = ScopedNote(
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                body: legacy.body,
                scope: legacy.scope,
                legacyFingerprint: legacy.legacyFingerprint,
                migrationKey: mk,
                studentLesson: nil,
                work: nil,
                presentation: presentation,
                workContract: nil
            )
            modelContext.insert(newNote)
            existingKeys.insert(mk)
        }

        // B) StudentLesson freeform notes string → Presentation (single group note)
        let trimmedNotesString = studentLesson.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotesString.isEmpty {
            let mk2 = "studentLessonNotesString:\(studentLesson.id.uuidString)"
            if !existingKeys.contains(mk2) {
                let created = studentLesson.givenAt ?? studentLesson.createdAt
                let newNote = ScopedNote(
                    createdAt: created,
                    updatedAt: created,
                    body: trimmedNotesString,
                    scope: .all,
                    legacyFingerprint: nil,
                    migrationKey: mk2,
                    studentLesson: nil,
                    work: nil,
                    presentation: presentation,
                    workContract: nil
                )
                modelContext.insert(newNote)
                existingKeys.insert(mk2)
            }
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

