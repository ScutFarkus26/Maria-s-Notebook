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

    private static func safeFetch<T>(_ descriptor: FetchDescriptor<T>, using context: ModelContext, caller: String = #function) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }
    /// Cleans orphaned student IDs from a LessonAssignment by removing IDs that no longer exist in the database.
    /// This ensures referential integrity when using manual ID management instead of SwiftData relationships.
    static func cleanOrphanedStudentIDs(
        for lessonAssignment: LessonAssignment,
        validStudentIDs: Set<String>,
        modelContext: ModelContext
    ) {
        let originalIDs = lessonAssignment.studentIDs
        let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }
        if cleanedIDs.count != originalIDs.count {
            lessonAssignment.studentIDs = cleanedIDs
            // Also update the transient relationship array
            lessonAssignment.students = lessonAssignment.students.filter { student in
                validStudentIDs.contains(student.cloudKitKey)
            }
        }
    }

    /// Record a LessonAssignment as presented and upsert LessonPresentation records,
    /// but do NOT auto-create WorkModel items. Use this when work creation is handled separately
    /// (e.g., via the unified workflow panel or explicit user action).
    static func recordPresentation(
        from lessonAssignment: LessonAssignment,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> LessonAssignment {
        // CRITICAL: Clean orphaned student IDs before processing to prevent ghost data
        let allStudents = try modelContext.fetch(FetchDescriptor<Student>())
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        cleanOrphanedStudentIDs(for: lessonAssignment, validStudentIDs: validStudentIDs, modelContext: modelContext)

        let lessonIDStr = lessonAssignment.lessonID
        let studentIDStrs = lessonAssignment.studentIDs

        // Update to presented state if not already
        if lessonAssignment.state != .presented {
            lessonAssignment.markPresented(at: presentedAt)
        }

        // Update track info if not already set
        if lessonAssignment.trackID == nil, let lesson = lessonAssignment.lesson {
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
                        let allSteps = safeFetch(FetchDescriptor<TrackStep>(), using: modelContext, caller: "recordPresentation")
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

        // Upsert LessonPresentation records per student (for individual progress tracking)
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

    /// Record a LessonAssignment as presented and create per-student WorkModel items.
    /// Idempotent by (presentationID, studentID) on WorkModel.
    ///
    /// Only use this when work items should be explicitly created (e.g., GiveLessonViewModel with needsPractice,
    /// or the syncAllStudentProgress migration path).
    static func recordPresentationAndExplodeWork(
        from lessonAssignment: LessonAssignment,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (lessonAssignment: LessonAssignment, work: [WorkModel]) {
        let la = try recordPresentation(
            from: lessonAssignment,
            presentedAt: presentedAt,
            modelContext: modelContext
        )

        let lessonIDStr = la.lessonID
        let studentIDStrs = la.studentIDs

        // Ensure WorkModels exist per student
        var workForPresentation: [WorkModel] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            // Check for existing WorkModel first
            if let existing = try fetchWorkModel(presentationID: la.id.uuidString, studentID: sid, context: modelContext) {
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
                        presentationID: la.id,
                        scheduledDate: nil
                    )

                    // Link WorkModel to Track if lesson belongs to a track
                    if let lesson = la.lesson {
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
                    logger.warning("Failed to create WorkModel for LessonAssignment \(la.id.uuidString, privacy: .public), student \(sid, privacy: .public): \(error.localizedDescription)")
                }
            }
        }

        // Fetch all associated WorkModels for this assignment
        let allForAssignment = try fetchAllWorkModels(presentationID: la.id.uuidString, context: modelContext)

        return (la, allForAssignment)
    }

    // MARK: - Fetch Helpers

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
    /// Used for syncing progress from LessonAssignment records that may not have a Presentation yet.
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

    /// Synchronizes student progress by updating LessonPresentation records from LessonAssignment and WorkModel data.
    /// This ensures all presented/completed lessons are properly tracked in the progress system.
    /// - Parameters:
    ///   - context: The ModelContext to operate on
    /// - Returns: A tuple with counts of (presentations created/updated, presentations marked as mastered)
    static func syncAllStudentProgress(context: ModelContext) throws -> (presentationsUpdated: Int, mastered: Int) {
        var presentationsUpdated = 0
        var mastered = 0

        // 1. Find all LessonAssignment records where lesson is presented (isGiven == true)
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let allLessonAssignments = try context.fetch(
            FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.stateRaw == presentedRaw })
        )

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

        // 3. For each presented LessonAssignment, ensure LessonPresentation records exist
        for la in allLessonAssignments {
            // Clean orphaned IDs
            cleanOrphanedStudentIDs(for: la, validStudentIDs: validStudentIDs, modelContext: context)

            // Skip if no valid students or invalid lessonID
            guard !la.studentIDs.isEmpty,
                  !la.lessonID.isEmpty,
                  UUID(uuidString: la.lessonID) != nil else { continue }

            // Determine presented date
            let presentedAt = la.presentedAt ?? la.createdAt

            // Get lesson - try relationship first, then lookup
            let lesson: Lesson?
            if let relationshipLesson = la.lesson {
                lesson = relationshipLesson
            } else {
                lesson = lessonsByID[la.lessonID]
            }

            // Validate lesson exists before attempting to sync
            guard lesson != nil else {
                logger.warning("Skipping LessonAssignment \(la.id, privacy: .public): lesson not found for lessonID \(la.lessonID, privacy: .public)")
                continue
            }

            // Use the lifecycle service to create LessonPresentation records and work items
            // This is idempotent, so safe to call multiple times
            do {
                // Ensure lesson is set on LessonAssignment if not already set
                if la.lesson == nil, let fetchedLesson = lesson {
                    la.lesson = fetchedLesson
                }

                let (updatedLA, _) = try recordPresentationAndExplodeWork(
                    from: la,
                    presentedAt: presentedAt,
                    modelContext: context
                )
                presentationsUpdated += la.studentIDs.count

                // Update presentationID on any LessonPresentation records that were created without it
                let assignmentIDStr = updatedLA.id.uuidString
                let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
                for studentIDStr in la.studentIDs {
                    if let lp = allLessonPresentations.first(where: {
                        $0.lessonID == la.lessonID &&
                        $0.studentID == studentIDStr &&
                        $0.presentationID == nil
                    }) {
                        lp.presentationID = assignmentIDStr
                    }
                }
            } catch {
                // If recordPresentationAndExplodeWork fails (e.g., lesson not found),
                // still try to create LessonPresentation record directly
                logger.warning("Failed to process LessonAssignment \(la.id, privacy: .public): \(error.localizedDescription)")

                // Fallback: create LessonPresentation directly
                for studentIDStr in la.studentIDs {
                    try upsertLessonPresentationByLessonAndStudent(
                        lessonID: la.lessonID,
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
                        studentIDs: la.studentIDs,
                        modelContext: context
                    )

                    // Update trackID on LessonPresentation records for this lesson+student combo
                    let trackID = "\(lesson.subject.trimmed())|\(lesson.group.trimmed())"
                    let allLessonPresentations = safeFetch(FetchDescriptor<LessonPresentation>(), using: context, caller: "syncAllStudentProgress")
                    for studentIDStr in la.studentIDs {
                        if let lp = allLessonPresentations.first(where: {
                            $0.lessonID == la.lessonID &&
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

            // Get lessonID from presentationID — look up the LessonAssignment
            guard let workPresentationID = work.presentationID else { continue }

            // Find the LessonAssignment to get lessonID and studentIDs
            guard let la = allLessonAssignments.first(where: { $0.id.uuidString == workPresentationID }) else {
                continue
            }

            let lessonIDStr = la.lessonID

            // Check participants for per-student completion
            let participants = work.participants ?? []

            if participants.isEmpty {
                // No participants: check global completion status
                if isWorkCompleted {
                    // Mark all students in the lesson as mastered
                    for studentIDStr in la.studentIDs {
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
