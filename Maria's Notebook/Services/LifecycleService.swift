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
    
    /// Record a Presentation (immutable) and create per-student WorkModel items.
    /// Idempotent by `legacyStudentLessonID` on Presentation and (presentationID, studentID) on WorkModel.
    static func recordPresentationAndExplodeWork(
        from studentLesson: StudentLesson,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (presentation: Presentation, work: [WorkModel]) {
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
            // Update existing presentation with track info if not already set
            if presentation.trackID == nil, let lesson = studentLesson.lesson {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                if !subject.isEmpty && !group.isEmpty,
                   GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext),
                   let track = try? GroupTrackService.getOrCreateTrack(
                       subject: subject,
                       group: group,
                       modelContext: modelContext
                   ) {
                    presentation.trackID = track.id.uuidString
                    // Find the TrackStep for this lesson
                    if let lessonUUID = UUID(uuidString: lessonIDStr) {
                        let allSteps = (try? modelContext.fetch(FetchDescriptor<TrackStep>())) ?? []
                        if let step = allSteps.first(where: { 
                            $0.track?.id == track.id && $0.lessonTemplateID == lessonUUID 
                        }) {
                            presentation.trackStepID = step.id.uuidString
                        }
                    }
                }
            }
        } else {
            // Create new Presentation
            let title = studentLesson.lesson?.name
            let subtitle = studentLesson.lesson?.subheading
            
            // Link to Track if lesson belongs to a track
            var trackID: String? = nil
            var trackStepID: String? = nil
            if let lesson = studentLesson.lesson {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                if !subject.isEmpty && !group.isEmpty,
                   GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext),
                   let track = try? GroupTrackService.getOrCreateTrack(
                       subject: subject,
                       group: group,
                       modelContext: modelContext
                   ) {
                    trackID = track.id.uuidString
                    // Find the TrackStep for this lesson
                    if let lessonUUID = UUID(uuidString: lessonIDStr) {
                        let allSteps = (try? modelContext.fetch(FetchDescriptor<TrackStep>())) ?? []
                        if let step = allSteps.first(where: { 
                            $0.track?.id == track.id && $0.lessonTemplateID == lessonUUID 
                        }) {
                            trackStepID = step.id.uuidString
                        }
                    }
                }
            }
            
            presentation = Presentation(
                id: UUID(),
                createdAt: Date(),
                presentedAt: presentedAt,
                lessonID: lessonIDStr,
                studentIDs: studentIDStrs,
                legacyStudentLessonID: legacyID,
                trackID: trackID,
                trackStepID: trackStepID,
                lessonTitleSnapshot: title,
                lessonSubtitleSnapshot: subtitle
            )
            modelContext.insert(presentation)
            #if DEBUG
            print("Presentation link set: legacyStudentLessonID=\(presentation.legacyStudentLessonID ?? "nil")")
            #endif
        }

        // Legacy note migration has been completed. All notes are now in the unified Note system.

        // 2) Ensure WorkModels exist per student
        var workForPresentation: [WorkModel] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            // Check for existing WorkModel first
            if let existing = try fetchWorkModel(presentationID: presentation.id.uuidString, studentID: sid, context: modelContext) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                // Create new WorkModel
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
                    
                    // Link WorkModel to Track if lesson belongs to a track
                    // Note: WorkModel doesn't have trackID field, so we can't link directly
                    // The trackID will be set on the Presentation which is linked to this work
                    if let lesson = studentLesson.lesson {
                        let subject = lesson.subject.trimmed()
                        let group = lesson.group.trimmed()
                        if !subject.isEmpty && !group.isEmpty,
                           GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) {
                            // Track exists - WorkModel link will be handled via Presentation.trackID
                            _ = try? GroupTrackService.getOrCreateTrack(
                                subject: subject,
                                group: group,
                                modelContext: modelContext
                            )
                        }
                    }
                    
                    workForPresentation.append(workModel)
                    createdCount += 1
                } catch {
                    // WorkModel creation failed - log error
                    #if DEBUG
                    print("⚠️ Failed to create WorkModel for presentation \(presentation.id.uuidString), student \(sid): \(error)")
                    #endif
                }
            }
        }

        // 2.5) Upsert LessonPresentation records per student (shadow data for progress tracking)
        let presentationIDStr = presentation.id.uuidString
        for sid in studentIDStrs {
            try upsertLessonPresentation(
                presentationID: presentationIDStr,
                studentID: sid,
                lessonID: lessonIDStr,
                presentedAt: presentedAt,
                context: modelContext
            )
        }

        // 3) Fetch all associated WorkModels for this presentation (e.g., backfill ordering)
        let pid = presentation.id.uuidString
        let allForPresentation = try fetchAllWorkModels(presentationID: pid, context: modelContext)

        return (presentation, allForPresentation)
    }

    // MARK: - Fetch Helpers

    private static func fetchPresentation(byLegacyID legacyID: String, context: ModelContext) throws -> Presentation? {
        let descriptor = FetchDescriptor<Presentation>(predicate: #Predicate { $0.legacyStudentLessonID == legacyID })
        let arr = try context.fetch(descriptor)
        return arr.first
    }

    private static func fetchWorkModel(presentationID: String, studentID: String, context: ModelContext) throws -> WorkModel? {
        // Fetch all WorkModels and filter in memory
        let allWork = try context.fetch(FetchDescriptor<WorkModel>())
        return allWork.first { work in
            (work.presentationID ?? "") == presentationID && work.studentID == studentID
        }
    }

    private static func fetchAllWorkModels(presentationID: String, context: ModelContext) throws -> [WorkModel] {
        // Fetch all WorkModels and filter in memory
        let allWork = try context.fetch(FetchDescriptor<WorkModel>())
        return allWork.filter { work in
            (work.presentationID ?? "") == presentationID
        }
    }

    // MARK: - LessonPresentation Helpers

    /// Upsert LessonPresentation idempotently by (presentationID, studentID).
    /// Fetches all LessonPresentation records and filters in memory (no predicates).
    /// If exists: updates lastObservedAt. If not exists: creates new with state .presented.
    private static func upsertLessonPresentation(
        presentationID: String,
        studentID: String,
        lessonID: String,
        presentedAt: Date,
        context: ModelContext
    ) throws {
        // Fetch all LessonPresentation records and filter in memory (no predicates)
        let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        let existing = allLessonPresentations.first { lp in
            lp.presentationID == presentationID && lp.studentID == studentID
        }
        
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
        // Fetch all LessonPresentation records and filter in memory (no predicates)
        let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        
        // Look for existing by lessonID and studentID (with or without presentationID)
        let existing = allLessonPresentations.first { lp in
            lp.lessonID == lessonID && lp.studentID == studentID
        }
        
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
        var presentationsUpdated = 0
        var mastered = 0
        
        // 1. Find all StudentLesson records where lesson is presented (isGiven == true)
        let allStudentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
        let presentedStudentLessons = allStudentLessons.filter { $0.isGiven }
        
        // Clean orphaned student IDs
        let allStudents = try context.fetch(FetchDescriptor<Student>())
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        
        // 2. Fetch all lessons once to avoid repeated fetches
        let allLessons = try context.fetch(FetchDescriptor<Lesson>())
        let lessonsByID = Dictionary(uniqueKeysWithValues: allLessons.map { ($0.id.uuidString, $0) })
        
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
                    #if DEBUG
                    print("⚠️ Failed to create/get GroupTrack for \(subject)/\(group): \(error)")
                    #endif
                }
            }
        }
        // Save tracks created above
        try context.save()
        
        // 3. For each presented StudentLesson, ensure Presentation and LessonPresentation records exist
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
            
            // Use the existing lifecycle service to create Presentation and LessonPresentation records
            // This is idempotent, so safe to call multiple times
            do {
                // Ensure lesson is set on studentLesson if not already set
                if studentLesson.lesson == nil, let fetchedLesson = lesson {
                    studentLesson.lesson = fetchedLesson
                }
                
                let (presentation, _) = try recordPresentationAndExplodeWork(
                    from: studentLesson,
                    presentedAt: presentedAt,
                    modelContext: context
                )
                presentationsUpdated += studentLesson.studentIDs.count
                
                // Update presentationID on any LessonPresentation records that were created without it
                let presentationIDStr = presentation.id.uuidString
                let allLessonPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
                for studentIDStr in studentLesson.studentIDs {
                    if let lp = allLessonPresentations.first(where: { 
                        $0.lessonID == studentLesson.lessonID && 
                        $0.studentID == studentIDStr && 
                        $0.presentationID == nil 
                    }) {
                        lp.presentationID = presentationIDStr
                    }
                }
            } catch {
                // If recordPresentationAndExplodeWork fails (e.g., lesson not found),
                // still try to create LessonPresentation record directly
                #if DEBUG
                print("⚠️ Failed to create Presentation for StudentLesson \(studentLesson.id): \(error)")
                #endif
                
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
                        #if DEBUG
                        print("⚠️ Failed to create/get GroupTrack for \(lesson.subject)/\(lesson.group): \(error)")
                        #endif
                    }
                    
                    // Enroll students in the track
                    GroupTrackService.autoEnrollInTrackIfNeeded(
                        lesson: lesson,
                        studentIDs: studentLesson.studentIDs,
                        modelContext: context
                    )
                    
                    // Update trackID on LessonPresentation records for this lesson+student combo
                    let trackID = "\(lesson.subject.trimmed())|\(lesson.group.trimmed())"
                    let allLessonPresentations = try? context.fetch(FetchDescriptor<LessonPresentation>())
                    for studentIDStr in studentLesson.studentIDs {
                        if let lp = allLessonPresentations?.first(where: { 
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

