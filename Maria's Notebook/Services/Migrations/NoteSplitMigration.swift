import Foundation
import SwiftData

/// Migration service to split polymorphic Note model into domain-specific note types.
///
/// **Phase 3C: Data Migration**
///
/// This service migrates existing Note records to the appropriate domain-specific type:
/// - LessonNote (for notes attached to Lesson)
/// - WorkNote (for notes attached to WorkModel, WorkCheckIn, WorkCompletionRecord, WorkPlanItem)
/// - StudentNote (for notes attached to StudentLesson, StudentMeeting)
/// - AttendanceNote (for notes attached to AttendanceRecord)
/// - PresentationNote (for notes attached to Presentation/LessonAssignment)
/// - ProjectNote (for notes attached to ProjectSession)
/// - GeneralNote (for standalone notes or secondary entities)
///
/// **Safety Features:**
/// - Idempotent: Can be run multiple times safely (checks MigrationFlag)
/// - Validation: Verifies note count matches after migration
/// - Error tracking: Reports failed migrations
/// - Preserves old Note records (only marks as migrated)
///
/// **Usage:**
/// ```swift
/// let success = try await NoteSplitMigration.execute(context: modelContext)
/// if success {
///     print("Migration completed successfully")
/// }
/// ```
@MainActor
struct NoteSplitMigration {
    
    // MARK: - Migration Flag
    
    enum MigrationKey: String {
        case noteSplit = "migration.noteSplit.completed"
    }
    
    // MARK: - Public API
    
    /// Execute the Note split migration.
    ///
    /// - Parameter context: The ModelContext to perform the migration in
    /// - Returns: True if migration completed successfully, false if already migrated
    /// - Throws: NoteSplitError if migration fails
    static func execute(context: ModelContext) async throws -> Bool {
        // Check if already migrated
        if isMigrated(in: context) {
            print("[NoteSplitMigration] Already migrated, skipping")
            return false
        }
        
        print("[NoteSplitMigration] Starting migration...")
        
        // Fetch all existing notes
        let descriptor = FetchDescriptor<Note>()
        let allNotes = try context.fetch(descriptor)
        
        print("[NoteSplitMigration] Found \(allNotes.count) notes to migrate")
        
        var migratedCount = 0
        var errorCount = 0
        var errors: [(UUID, Error)] = []
        
        // Migrate each note
        for note in allNotes {
            do {
                try migrateNote(note, context: context)
                migratedCount += 1
                
                // Log progress every 50 notes
                if migratedCount % 50 == 0 {
                    print("[NoteSplitMigration] Migrated \(migratedCount)/\(allNotes.count) notes...")
                }
            } catch {
                errorCount += 1
                errors.append((note.id, error))
                print("[NoteSplitMigration] Failed to migrate note \(note.id): \(error)")
            }
        }
        
        print("[NoteSplitMigration] Migration complete: \(migratedCount) migrated, \(errorCount) failed")
        
        // Validation: Verify note counts
        try validateMigration(
            originalCount: allNotes.count,
            context: context
        )
        
        // If any errors occurred, throw
        guard errorCount == 0 else {
            throw NoteSplitError.partialFailure(
                migrated: migratedCount,
                failed: errorCount,
                errors: errors
            )
        }
        
        // Mark migration complete
        setMigrated(in: context)
        
        print("[NoteSplitMigration] Migration successful!")
        return true
    }
    
    // MARK: - Migration Logic
    
    /// Migrate a single Note to the appropriate domain-specific type.
    private static func migrateNote(_ note: Note, context: ModelContext) throws {
        // Determine the appropriate domain-specific type based on relationships
        
        if let lesson = note.lesson {
            // LessonNote
            let lessonNote = LessonNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt, // Note: Note uses updatedAt, not modifiedAt
                authorID: nil, // Note model doesn't have authorID
                category: note.category,
                lesson: lesson,
                scope: note.scope
            )
            context.insert(lessonNote)
        }
        else if let work = note.work {
            // WorkNote
            let workNote = WorkNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt,
                authorID: nil,
                category: note.category,
                work: work,
                checkInID: note.workCheckIn?.id.uuidString,
                completionRecordID: note.workCompletionRecord?.id.uuidString,
                workPlanItemID: note.workPlanItem?.id.uuidString
            )
            context.insert(workNote)
        }
        else if let studentLesson = note.studentLesson {
            // StudentNote (one per student in the lesson)
            for student in studentLesson.students {
                let studentNote = StudentNote(
                    id: UUID(), // Generate new ID for each student copy
                    content: note.body,
                    createdAt: note.createdAt,
                    modifiedAt: note.updatedAt,
                    authorID: nil,
                    category: note.category,
                    student: student,
                    studentLessonID: studentLesson.id.uuidString
                )
                context.insert(studentNote)
            }
        }
        else if let studentMeeting = note.studentMeeting {
            // StudentNote (lookup student by studentID)
            if let studentUUID = UUID(uuidString: studentMeeting.studentID) {
                let studentDescriptor = FetchDescriptor<Student>(
                    predicate: #Predicate<Student> { $0.id == studentUUID }
                )
                if let student = try context.fetch(studentDescriptor).first {
                    let studentNote = StudentNote(
                        id: note.id,
                        content: note.body,
                        createdAt: note.createdAt,
                        modifiedAt: note.updatedAt,
                        authorID: nil,
                        category: note.category,
                        student: student,
                        meetingID: studentMeeting.id.uuidString
                    )
                    context.insert(studentNote)
                }
            }
        }
        else if let attendanceRecord = note.attendanceRecord {
            // AttendanceNote
            let attendanceNote = AttendanceNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt,
                authorID: nil,
                category: note.category,
                attendance: attendanceRecord
            )
            context.insert(attendanceNote)
        }
        else if let presentation = note.lessonAssignment {
            // PresentationNote
            let presentationNote = PresentationNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt,
                authorID: nil,
                category: note.category,
                presentation: presentation,
                scope: note.scope
            )
            context.insert(presentationNote)
        }
        else if let projectSession = note.projectSession {
            // ProjectNote
            let projectNote = ProjectNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt,
                authorID: nil,
                category: note.category,
                projectSession: projectSession
            )
            context.insert(projectNote)
        }
        else {
            // GeneralNote (standalone or secondary entity notes)
            let generalNote = GeneralNote(
                id: note.id,
                content: note.body,
                createdAt: note.createdAt,
                modifiedAt: note.updatedAt,
                authorID: nil,
                category: note.category,
                scope: note.scope,
                communityTopicID: note.communityTopic?.id.uuidString,
                reminderID: note.reminder?.id.uuidString,
                issueID: note.issue?.id.uuidString,
                schoolDayOverrideID: note.schoolDayOverride?.id.uuidString,
                trackEnrollmentID: note.studentTrackEnrollment?.id.uuidString, // Note: uses studentTrackEnrollment
                practiceSessionID: note.practiceSession?.id.uuidString
            )
            context.insert(generalNote)
        }
    }
    
    // MARK: - Validation
    
    /// Validate that migration was successful by comparing note counts.
    private static func validateMigration(
        originalCount: Int,
        context: ModelContext
    ) throws {
        let lessonNoteCount = try context.fetchCount(FetchDescriptor<LessonNote>())
        let workNoteCount = try context.fetchCount(FetchDescriptor<WorkNote>())
        let studentNoteCount = try context.fetchCount(FetchDescriptor<StudentNote>())
        let attendanceNoteCount = try context.fetchCount(FetchDescriptor<AttendanceNote>())
        let presentationNoteCount = try context.fetchCount(FetchDescriptor<PresentationNote>())
        let projectNoteCount = try context.fetchCount(FetchDescriptor<ProjectNote>())
        let generalNoteCount = try context.fetchCount(FetchDescriptor<GeneralNote>())
        
        let totalMigrated = lessonNoteCount + workNoteCount + studentNoteCount +
                           attendanceNoteCount + presentationNoteCount +
                           projectNoteCount + generalNoteCount
        
        print("[NoteSplitMigration] Validation:")
        print("  - Original notes: \(originalCount)")
        print("  - LessonNote: \(lessonNoteCount)")
        print("  - WorkNote: \(workNoteCount)")
        print("  - StudentNote: \(studentNoteCount)")
        print("  - AttendanceNote: \(attendanceNoteCount)")
        print("  - PresentationNote: \(presentationNoteCount)")
        print("  - ProjectNote: \(projectNoteCount)")
        print("  - GeneralNote: \(generalNoteCount)")
        print("  - Total migrated: \(totalMigrated)")
        
        // Note: StudentNote count may be higher than original if StudentLesson notes
        // were split into multiple notes (one per student)
        guard totalMigrated >= originalCount else {
            throw NoteSplitError.validationFailed(
                expected: originalCount,
                actual: totalMigrated,
                message: "Migrated note count is less than original"
            )
        }
        
        print("[NoteSplitMigration] Validation passed!")
    }
    
    // MARK: - Migration Flag Management
    
    /// Check if the migration has already been executed.
    private static func isMigrated(in context: ModelContext) -> Bool {
        // Check UserDefaults for migration flag
        return UserDefaults.standard.bool(forKey: MigrationKey.noteSplit.rawValue)
    }
    
    /// Mark the migration as complete.
    private static func setMigrated(in context: ModelContext) {
        UserDefaults.standard.set(true, forKey: MigrationKey.noteSplit.rawValue)
        UserDefaults.standard.synchronize()
        print("[NoteSplitMigration] Migration flag set")
    }
    
    /// Reset the migration flag (for testing only).
    static func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: MigrationKey.noteSplit.rawValue)
        UserDefaults.standard.synchronize()
        print("[NoteSplitMigration] Migration flag reset")
    }
    
    // MARK: - Rollback (Future Implementation)
    
    /// Reverse the migration (future implementation).
    ///
    /// **Note:** Rollback is complex because:
    /// - Domain-specific notes need to be merged back into polymorphic Note
    /// - Student notes may have been split (one per student) and need recombining
    /// - New notes created after migration need special handling
    ///
    /// For now, rollback is handled by restoring from backup before migration.
    static func reverse(context: ModelContext) async throws {
        // Rollback implementation will be added if needed
        // For Phase 3B-3E, we keep old Note records for safety
        print("[NoteSplitMigration] Rollback not yet implemented - restore from backup instead")
        throw NoteSplitError.alreadyMigrated // Placeholder error
    }
}

// MARK: - NoteSplit-Specific Errors

enum NoteSplitError: Error, LocalizedError {
    case partialFailure(migrated: Int, failed: Int, errors: [(UUID, Error)])
    case validationFailed(expected: Int, actual: Int, message: String)
    case alreadyMigrated
    
    var errorDescription: String? {
        switch self {
        case .partialFailure(let migrated, let failed, let errors):
            let errorDetails = errors.prefix(5).map { "\($0.0): \($0.1.localizedDescription)" }.joined(separator: "\n  ")
            return """
            Note split migration partially failed:
            - Migrated: \(migrated)
            - Failed: \(failed)
            - First 5 errors:
              \(errorDetails)
            """
        case .validationFailed(let expected, let actual, let message):
            return "Note split validation failed: expected \(expected), got \(actual). \(message)"
        case .alreadyMigrated:
            return "Note split migration already completed"
        }
    }
}
