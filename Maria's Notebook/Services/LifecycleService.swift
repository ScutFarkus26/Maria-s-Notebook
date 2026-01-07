import Foundation
import SwiftData

struct LifecycleService {
    /// Cleans orphaned student IDs from a StudentLesson by removing IDs that no longer exist in the database.
    /// This ensures referential integrity when using manual ID management instead of SwiftData relationships.
    static func cleanOrphanedStudentIDs(
        for studentLesson: StudentLesson,
        validStudentIDs: Set<String>,
        modelContext: ModelContext
    ) {
        let originalIDs = studentLesson.studentIDs
        let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }
        if cleanedIDs.count != originalIDs.count {
            studentLesson.studentIDs = cleanedIDs
            // Also update the transient relationship array
            studentLesson.students = studentLesson.students.filter { student in
                validStudentIDs.contains(student.id.uuidString)
            }
        }
    }
    
    /// Record a Presentation (immutable) and create per-student WorkContract items.
    /// Idempotent by `legacyStudentLessonID` on Presentation and (presentationID, studentID) on WorkContract.
    static func recordPresentationAndExplodeWork(
        from studentLesson: StudentLesson,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (presentation: Presentation, work: [WorkContract]) {
        // CRITICAL: Clean orphaned student IDs before processing to prevent ghost data
        let allStudents = try modelContext.fetch(FetchDescriptor<Student>())
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        cleanOrphanedStudentIDs(for: studentLesson, validStudentIDs: validStudentIDs, modelContext: modelContext)
        
        let legacyID = studentLesson.id.uuidString
        // CloudKit compatibility: lessonID is already String
        let lessonIDStr = studentLesson.lessonID
        // studentIDs is already [String] for CloudKit compatibility (now cleaned of orphans)
        let studentIDStrs = studentLesson.studentIDs

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
        for legacy in studentLesson.scopedNotes ?? [] {
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
                    presentation: presentation,
                    workContract: nil
                )
                modelContext.insert(newNote)
                existingKeys.insert(mk2)
            }
        }

        // 2) Ensure WorkModels exist per student (WorkContract is now read-only for legacy data)
        var workForPresentation: [WorkContract] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            // Check for existing WorkContract first (for backward compatibility)
            if let existing = try fetchWorkContract(presentationID: presentation.id.uuidString, studentID: sid, context: modelContext) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                // Create new WorkModel (WorkContract is read-only - no new WorkContract creation)
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lessonIDStr),
                      let presentationUUID = UUID(uuidString: presentation.id.uuidString) else {
                    continue
                }
                
                let repository = WorkRepository(context: modelContext)
                do {
                    let workModel = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonUUID,
                        title: nil,
                        kind: .practiceLesson,
                        presentationID: presentationUUID,
                        scheduledDate: nil
                    )
                    
                    // For backward compatibility, try to find an existing WorkContract by legacyContractID
                    // Do NOT create new WorkContract - it is read-only for legacy data only
                    if let contractID = workModel.legacyContractID {
                        // Fetch all WorkContracts and filter in memory (no predicates on WorkContract)
                        let allContracts = (try? modelContext.fetch(FetchDescriptor<WorkContract>())) ?? []
                        if let contract = allContracts.first(where: { $0.id == contractID }) {
                            workForPresentation.append(contract)
                        }
                    }
                    // If no legacy contract exists, that's fine - WorkModel is the source of truth
                    createdCount += 1
                } catch {
                    // WorkModel creation failed - log error but do not create WorkContract
                    // WorkContract is read-only for legacy data only
                    #if DEBUG
                    print("⚠️ Failed to create WorkModel for presentation \(presentation.id.uuidString), student \(sid): \(error)")
                    #endif
                    // Do not create WorkContract - it is deprecated
                }
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

