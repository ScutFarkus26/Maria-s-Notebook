import Foundation
import SwiftData
import OSLog

/// Errors that can occur during lifecycle operations
enum LifecycleError: Error {
    case invalidLessonID(String)
    case invalidStudentID(String)
}

@MainActor
struct LifecycleService {
    private static let logger = Logger.lifecycle

    // MARK: - Helper Methods

    private static func safeFetch<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }

    private static var modelContext: ModelContext!

    private static func setModelContext(_ context: ModelContext) {
        modelContext = context
    }
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
                validStudentIDs.contains(student.cloudKitKey)
            }
        }
    }

    /// Record a LessonAssignment (the unified presentation model) and upsert LessonPresentation records,
    /// but do NOT auto-create WorkModel items. Use this when work creation is handled separately
    /// (e.g., via the unified workflow panel or explicit user action).
    /// Idempotent by `migratedFromStudentLessonID` on LessonAssignment.
    static func recordPresentation(
        from studentLesson: StudentLesson,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> LessonAssignment {
        setModelContext(modelContext)
        // CRITICAL: Clean orphaned student IDs before processing to prevent ghost data
        let allStudents = try modelContext.fetch(FetchDescriptor<Student>())
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        cleanOrphanedStudentIDs(for: studentLesson, validStudentIDs: validStudentIDs, modelContext: modelContext)

        let legacyID = studentLesson.id.uuidString
        let lessonIDStr = studentLesson.lessonID
        let studentIDStrs = studentLesson.studentIDs

        // 1) Lookup existing LessonAssignment by legacy link (migrated from StudentLesson)
        let existingAssignment: LessonAssignment? = try fetchLessonAssignment(byMigratedStudentLessonID: legacyID, context: modelContext)

        let lessonAssignment: LessonAssignment
        if let existing = existingAssignment {
            lessonAssignment = existing
            // Update to presented state if not already
            if lessonAssignment.state != .presented {
                lessonAssignment.markPresented(at: presentedAt)
            }
            // Update existing assignment with track info if not already set
            if lessonAssignment.trackID == nil, let lesson = studentLesson.lesson {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                if !subject.isEmpty && !group.isEmpty,
                   GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                    do {
                        let track = try GroupTrackService.getOrCreateTrack(
                            subject: subject,
                            group: group,
                            modelContext: modelContext
                        )
                        lessonAssignment.trackID = track.id.uuidString
                        if let lessonUUID = UUID(uuidString: lessonIDStr) {
                            let allSteps = safeFetch(FetchDescriptor<TrackStep>(), context: "recordPresentation")
                            if let step = allSteps.first(where: {
                                $0.track?.id == track.id && $0.lessonTemplateID == lessonUUID
                            }) {
                                lessonAssignment.trackStepID = step.id.uuidString
                            }
                        }
                    } catch {
                        logger.warning("Failed to get or create track: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Create new LessonAssignment in presented state
            let title = studentLesson.lesson?.name
            let subtitle = studentLesson.lesson?.subheading

            var trackID: String? = nil
            var trackStepID: String? = nil
            if let lesson = studentLesson.lesson {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                if !subject.isEmpty && !group.isEmpty,
                   GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                    do {
                        let track = try GroupTrackService.getOrCreateTrack(
                            subject: subject,
                            group: group,
                            modelContext: modelContext
                        )
                        trackID = track.id.uuidString
                        if let lessonUUID = UUID(uuidString: lessonIDStr) {
                            let allSteps = safeFetch(FetchDescriptor<TrackStep>(), context: "recordPresentation")
                            if let step = allSteps.first(where: {
                                $0.track?.id == track.id && $0.lessonTemplateID == lessonUUID
                            }) {
                                trackStepID = step.id.uuidString
                            }
                        }
                    } catch {
                        logger.warning("Failed to get or create track: \(error.localizedDescription)")
                    }
                }
            }

            let studentUUIDs = studentIDStrs.compactMap { UUID(uuidString: $0) }
            guard !studentUUIDs.isEmpty else {
                throw LifecycleError.invalidStudentID("No valid student IDs in StudentLesson \(studentLesson.id)")
            }
            guard let lessonUUID = UUID(uuidString: lessonIDStr) else {
                throw LifecycleError.invalidLessonID(lessonIDStr)
            }

            lessonAssignment = LessonAssignment(
                id: UUID(),
                createdAt: Date(),
                state: .presented,
                presentedAt: presentedAt,
                lessonID: lessonUUID,
                studentIDs: studentUUIDs,
                lesson: studentLesson.lesson,
                trackID: trackID,
                trackStepID: trackStepID
            )
            lessonAssignment.lessonTitleSnapshot = title
            lessonAssignment.lessonSubheadingSnapshot = subtitle
            lessonAssignment.migratedFromStudentLessonID = legacyID

            modelContext.insert(lessonAssignment)
            logger.debug("LessonAssignment created: migratedFromStudentLessonID=\(lessonAssignment.migratedFromStudentLessonID ?? "nil", privacy: .public)")
        }

        // 2) Upsert LessonPresentation records per student (for individual progress tracking)
        let assignmentIDStr = lessonAssignment.id.uuidString
        for sid in studentIDStrs {
            try upsertLessonPresentation(
                presentationID: assignmentIDStr,
                studentID: sid,
                lessonID: lessonIDStr,
                presentedAt: presentedAt,
                context: modelContext
            )
        }

        return lessonAssignment
    }

    /// Record a LessonAssignment (the unified presentation model) and create per-student WorkModel items.
    /// Idempotent by `migratedFromStudentLessonID` on LessonAssignment and (presentationID, studentID) on WorkModel.
    ///
    /// Only use this when work items should be explicitly created (e.g., GiveLessonViewModel with needsPractice,
    /// or the syncAllStudentProgress migration path).
    static func recordPresentationAndExplodeWork(
        from studentLesson: StudentLesson,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (lessonAssignment: LessonAssignment, work: [WorkModel]) {
        let lessonAssignment = try recordPresentation(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: modelContext
        )

        let lessonIDStr = studentLesson.lessonID
        let studentIDStrs = studentLesson.studentIDs

        // Ensure WorkModels exist per student
        var workForPresentation: [WorkModel] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            // Check for existing WorkModel first
            if let existing = try fetchWorkModel(presentationID: lessonAssignment.id.uuidString, studentID: sid, context: modelContext) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                // Create new WorkModel
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lessonIDStr) else {
                    continue
                }

                let repository = WorkRepository(context: modelContext)
                do {
                    let workModel = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonUUID,
                        title: nil,
                        kind: .practiceLesson,
                        presentationID: lessonAssignment.id,
                        scheduledDate: nil
                    )

                    // Link WorkModel to Track if lesson belongs to a track
                    if let lesson = studentLesson.lesson {
                        let subject = lesson.subject.trimmed()
                        let group = lesson.group.trimmed()
                        if !subject.isEmpty && !group.isEmpty,
                           GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                            do {
                                _ = try GroupTrackService.getOrCreateTrack(
                                    subject: subject,
                                    group: group,
                                    modelContext: modelContext
                                )
                            } catch {
                                logger.warning("Failed to link work to track: \(error.localizedDescription)")
                            }
                        }
                    }

                    workForPresentation.append(workModel)
                    createdCount += 1
                } catch {
                    logger.warning("Failed to create WorkModel for LessonAssignment \(lessonAssignment.id.uuidString, privacy: .public), student \(sid, privacy: .public): \(error.localizedDescription)")
                }
            }
        }

        // Fetch all associated WorkModels for this assignment
        let allForAssignment = try fetchAllWorkModels(presentationID: lessonAssignment.id.uuidString, context: modelContext)

        return (lessonAssignment, allForAssignment)
    }

    // MARK: - Fetch Helpers

    /// Fetches a LessonAssignment by the StudentLesson ID it was migrated from
    private static func fetchLessonAssignment(byMigratedStudentLessonID legacyID: String, context: ModelContext) throws -> LessonAssignment? {
        var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.migratedFromStudentLessonID == legacyID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchWorkModel(presentationID: String, studentID: String, context: ModelContext) throws -> WorkModel? {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.presentationID == presentationID && work.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        return try context.fetch(limitedDescriptor).first
    }

    private static func fetchAllWorkModels(presentationID: String, context: ModelContext) throws -> [WorkModel] {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.presentationID == presentationID
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - LessonPresentation Helpers

    /// Upsert LessonPresentation idempotently by (presentationID, studentID).
    /// If exists: updates lastObservedAt. If not exists: creates new with state .presented.
    private static func upsertLessonPresentation(
        presentationID: String,
        studentID: String,
        lessonID: String,
        presentedAt: Date,
        context: ModelContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.presentationID == presentationID && lp.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existing = try context.fetch(limitedDescriptor).first
        
        if let existing = existing {
            // Update lastObservedAt to track when this presentation was last seen
            existing.lastObservedAt = presentedAt
        } else {
            // Create new LessonPresentation with initial state .presented
            let lessonPresentation = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: presentationID,
                state: .presented,
                presentedAt: presentedAt,
                lastObservedAt: presentedAt
            )
            context.insert(lessonPresentation)
        }
    }
    
    /// Upsert LessonPresentation by (lessonID, studentID) when no presentationID exists.
    /// Used for syncing progress from StudentLesson records that may not have a Presentation yet.
    static func upsertLessonPresentationByLessonAndStudent(
        lessonID: String,
        studentID: String,
        presentedAt: Date,
        context: ModelContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.lessonID == lessonID && lp.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existing = try context.fetch(limitedDescriptor).first
        
        if let existing = existing {
            // Update lastObservedAt and presentedAt if the new date is earlier (preserve first presentation date)
            if presentedAt < existing.presentedAt {
                existing.presentedAt = presentedAt
            }
            existing.lastObservedAt = presentedAt
        } else {
            // Create new LessonPresentation with initial state .presented (no presentationID yet)
            let lessonPresentation = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: nil,
                state: .presented,
                presentedAt: presentedAt,
                lastObservedAt: presentedAt
            )
            context.insert(lessonPresentation)
        }
    }
    
    // MARK: - Progress Synchronization
    
    /// Synchronizes student progress by updating LessonPresentation records from StudentLesson and WorkModel data.
    /// This ensures all presented/completed lessons are properly tracked in the progress system.
    /// - Parameters:
    ///   - context: The ModelContext to operate on
    /// - Returns: A tuple with counts of (presentations created/updated, presentations marked as mastered)
    static func syncAllStudentProgress(context: ModelContext) throws -> (presentationsUpdated: Int, mastered: Int) {
        setModelContext(context)
        var presentationsUpdated = 0
        var mastered = 0
        
        // 1. Find all StudentLesson records where lesson is presented (isGiven == true)
        let allStudentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
        let presentedStudentLessons = allStudentLessons.filter { $0.isGiven }
        
        // Clean orphaned student IDs
        let allStudents = try context.fetch(FetchDescriptor<Student>())
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        
        // 2. Fetch all lessons once to avoid repeated fetches
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        let allLessons = try context.fetch(FetchDescriptor<Lesson>())
        let lessonsByID = Dictionary(allLessons.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        
        // 2.5. Create GroupTrack records for all subject/group combinations found in lessons
        // This ensures all groups are available as tracks in the progress tab
        var uniqueSubjectGroups: Set<String> = []
        for lesson in allLessons {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            guard !subject.isEmpty && !group.isEmpty else { continue }
            
            let key = "\(subject)|\(group)"
            guard !uniqueSubjectGroups.contains(key) else { continue }
            uniqueSubjectGroups.insert(key)
            
            // Check if this group should be a track (defaults to true unless explicitly disabled)
            if GroupTrackService.isTrack(subject: subject, group: group, modelContext: context) {
                // Create the GroupTrack record if it doesn't exist
                // This is idempotent - will return existing track if it exists
                do {
                    _ = try GroupTrackService.getOrCreateGroupTrack(
                        subject: subject,
                        group: group,
                        modelContext: context
                    )
                } catch {
                    logger.warning("Failed to create/get GroupTrack for \(subject, privacy: .public)/\(group, privacy: .public): \(error.localizedDescription)")
                }
            }
        }
        // Save tracks created above
        try context.save()
        
        // 3. For each presented StudentLesson, ensure LessonAssignment and LessonPresentation records exist
        for studentLesson in presentedStudentLessons {
            // Clean orphaned IDs
            cleanOrphanedStudentIDs(for: studentLesson, validStudentIDs: validStudentIDs, modelContext: context)

            // Skip if no valid students or invalid lessonID
            guard !studentLesson.studentIDs.isEmpty,
                  !studentLesson.lessonID.isEmpty,
                  UUID(uuidString: studentLesson.lessonID) != nil else { continue }

            // Determine presented date
            let presentedAt = studentLesson.givenAt ?? studentLesson.createdAt

            // Get lesson - try relationship first, then lookup
            let lesson: Lesson?
            if let relationshipLesson = studentLesson.lesson {
                lesson = relationshipLesson
            } else {
                lesson = lessonsByID[studentLesson.lessonID]
            }
            
            // Validate lesson exists before attempting to sync
            guard lesson != nil else {
                logger.warning("Skipping StudentLesson \(studentLesson.id, privacy: .public): lesson not found for lessonID \(studentLesson.lessonID, privacy: .public)")
                continue
            }

            // Use the lifecycle service to create LessonAssignment and LessonPresentation records
            // This is idempotent, so safe to call multiple times
            do {
                // Ensure lesson is set on studentLesson if not already set
                if studentLesson.lesson == nil, let fetchedLesson = lesson {
                    studentLesson.lesson = fetchedLesson
                }

                let (lessonAssignment, _) = try recordPresentationAndExplodeWork(
                    from: studentLesson,
                    presentedAt: presentedAt,
                    modelContext: context
                )
                presentationsUpdated += studentLesson.studentIDs.count

                // Update presentationID on any LessonPresentation records that were created without it
                let assignmentIDStr = lessonAssignment.id.uuidString
                let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
                for studentIDStr in studentLesson.studentIDs {
                    if let lp = allLessonPresentations.first(where: {
                        $0.lessonID == studentLesson.lessonID &&
                        $0.studentID == studentIDStr &&
                        $0.presentationID == nil
                    }) {
                        lp.presentationID = assignmentIDStr
                    }
                }
            } catch {
                // If recordPresentationAndExplodeWork fails (e.g., lesson not found),
                // still try to create LessonPresentation record directly
                logger.warning("Failed to create LessonAssignment for StudentLesson \(studentLesson.id, privacy: .public): \(error.localizedDescription)")

                // Fallback: create LessonPresentation directly
                for studentIDStr in studentLesson.studentIDs {
                    try upsertLessonPresentationByLessonAndStudent(
                        lessonID: studentLesson.lessonID,
                        studentID: studentIDStr,
                        presentedAt: presentedAt,
                        context: context
                    )
                    presentationsUpdated += 1
                }
            }
            
            // Auto-enroll students in track if lesson belongs to a track
            // This is critical for the progress tab to show data
            if let lesson = lesson {
                // Skip if subject or group is empty
                guard !lesson.subject.trimmed().isEmpty && !lesson.group.trimmed().isEmpty else { continue }

                // Check if lesson belongs to a track (defaults to true unless explicitly disabled)
                let belongsToTrack = GroupTrackService.isTrack(
                    subject: lesson.subject,
                    group: lesson.group,
                    modelContext: context
                )

                if belongsToTrack {
                    // CRITICAL: Create the GroupTrack record if it doesn't exist
                    // StudentProgressTab only shows tracks that have actual GroupTrack records
                    do {
                        _ = try GroupTrackService.getOrCreateGroupTrack(
                            subject: lesson.subject,
                            group: lesson.group,
                            modelContext: context
                        )
                    } catch {
                        logger.warning("Failed to create/get GroupTrack for \(lesson.subject, privacy: .public)/\(lesson.group, privacy: .public): \(error.localizedDescription)")
                    }

                    // Enroll students in the track
                    GroupTrackService.autoEnrollInTrackIfNeeded(
                        lesson: lesson,
                        studentIDs: studentLesson.studentIDs,
                        modelContext: context
                    )

                    // Update trackID on LessonPresentation records for this lesson+student combo
                    let trackID = "\(lesson.subject.trimmed())|\(lesson.group.trimmed())"
                    let allLessonPresentations = safeFetch(FetchDescriptor<LessonPresentation>(), context: "syncAllStudentProgress")
                    for studentIDStr in studentLesson.studentIDs {
                        if let lp = allLessonPresentations.first(where: {
                            $0.lessonID == studentLesson.lessonID &&
                            $0.studentID == studentIDStr
                        }) {
                            // Update trackID if not set or different
                            if lp.trackID != trackID {
                                lp.trackID = trackID
                            }
                        }
                    }
                }
            }
        }
        
        // 4. Re-fetch LessonPresentation records after creating new ones
        // Save context to ensure new records are available for querying
        try context.save()
        
        // 5. Find all WorkModel records and check for completed work
        let allWorkModels = try context.fetch(FetchDescriptor<WorkModel>())
        let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        
        for work in allWorkModels {
            // Check if work is completed (either globally or per-student via participants)
            let isWorkCompleted = work.status == .complete || work.completedAt != nil
            
            // Get lessonID from studentLessonID
            guard let studentLessonID = work.studentLessonID else { continue }
            
            // Find the StudentLesson to get lessonID and studentIDs
            guard let studentLesson = allStudentLessons.first(where: { $0.id == studentLessonID }) else {
                continue
            }
            
            let lessonIDStr = studentLesson.lessonID
            
            // Check participants for per-student completion
            let participants = work.participants ?? []
            
            if participants.isEmpty {
                // No participants: check global completion status
                if isWorkCompleted {
                    // Mark all students in the lesson as mastered
                    for studentIDStr in studentLesson.studentIDs {
                        if let lp = allLessonPresentations.first(where: { 
                            $0.lessonID == lessonIDStr && $0.studentID == studentIDStr 
                        }) {
                            if lp.state != .mastered || lp.masteredAt == nil {
                                lp.state = .mastered
                                lp.masteredAt = work.completedAt ?? work.lastTouchedAt ?? Date()
                                mastered += 1
                            }
                        }
                    }
                }
            } else {
                // Has participants: check per-student completion
                for participant in participants {
                    let studentIDStr = participant.studentID
                    guard !studentIDStr.isEmpty else { continue }
                    
                    // Participant is completed if they have a completion date
                    // OR if the work is globally completed (status complete or completedAt set)
                    let isParticipantCompleted = participant.completedAt != nil || isWorkCompleted
                    
                    if isParticipantCompleted {
                        // Find or create LessonPresentation for this student+lesson
                        if let lp = allLessonPresentations.first(where: { 
                            $0.lessonID == lessonIDStr && $0.studentID == studentIDStr 
                        }) {
                            if lp.state != .mastered || lp.masteredAt == nil {
                                lp.state = .mastered
                                lp.masteredAt = participant.completedAt ?? work.completedAt ?? work.lastTouchedAt ?? Date()
                                mastered += 1
                            }
                        }
                    }
                }
            }
        }
        
        // Save all changes
        try context.save()
        
        return (presentationsUpdated, mastered)
    }
}
