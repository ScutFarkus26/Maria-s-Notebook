import Foundation
import SwiftData
import OSLog

struct AvailableTrack {
    let subject: String
    let group: String
    let isSequential: Bool
}

/// Service for managing group-based tracks
@MainActor
struct GroupTrackService {
    private static let logger = Logger.lessons

    // MARK: - Helper Methods

    private static func safeFetch<T>(
        _ descriptor: FetchDescriptor<T>,
        modelContext: ModelContext,
        context: String = #function
    ) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }

    private static func safeSave(modelContext: ModelContext, context: String = #function) {
        do {
            try modelContext.save()
        } catch {
            logger.warning("Failed to save: \(error.localizedDescription)")
        }
    }
    /// Get or create a GroupTrack for the given subject and group
    /// Creates with default settings (sequential, not explicitly disabled)
    static func getOrCreateGroupTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> GroupTrack {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        
        // Fetch all GroupTracks and filter in memory (no predicates with string comparisons)
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        
        if let existing = allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        }) {
            return existing
        }
        
        // Create new GroupTrack with default settings (sequential, not explicitly disabled)
        let newTrack = GroupTrack(
            subject: trimmedSubject,
            group: trimmedGroup,
            isSequential: true, // Default to sequential
            isExplicitlyDisabled: false // Not explicitly disabled
        )
        modelContext.insert(newTrack)
        return newTrack
    }
    
    /// Get GroupTrack for subject and group, or nil if not found or if explicitly disabled
    /// Returns the actual record if it exists (even if disabled), for settings purposes
    static func getGroupTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> GroupTrack? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        
        return allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        })
    }
    
    /// Get effective track settings for a group (returns default if no record exists)
    /// This returns a GroupTrack with default settings (sequential) if no explicit record exists
    static func getEffectiveTrackSettings(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> (isSequential: Bool, isExplicitlyDisabled: Bool) {
        if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
            return (isSequential: track.isSequential, isExplicitlyDisabled: track.isExplicitlyDisabled)
        }
        // Default: sequential, not disabled
        return (isSequential: true, isExplicitlyDisabled: false)
    }
    
    /// Check if a group is marked as a track
    /// Default behavior: All groups are tracks (sequential) unless explicitly disabled.
    static func isTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) -> Bool {
        do {
            if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
                // If a record exists, check if it's explicitly disabled
                return !track.isExplicitlyDisabled
            }
            // No record exists = default behavior = is a track
            return true
        } catch {
            // On error, default to true (is a track)
            return true
        }
    }
    
    /// Remove track designation from a group (explicitly disable)
    /// Instead of deleting, we mark it as explicitly disabled
    static func removeTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws {
        if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
            // Mark as explicitly disabled instead of deleting
            track.isExplicitlyDisabled = true
        } else {
            // Create a record to mark it as explicitly disabled
            let disabledTrack = GroupTrack(
                subject: subject.trimmed(),
                group: group.trimmed(),
                isSequential: true,
                isExplicitlyDisabled: true
            )
            modelContext.insert(disabledTrack)
        }
    }
    
    /// Get all group tracks (only records that exist)
    static func getAllGroupTracks(modelContext: ModelContext) throws -> [GroupTrack] {
        return try modelContext.fetch(FetchDescriptor<GroupTrack>(
            sortBy: [SortDescriptor(\.subject), SortDescriptor(\.group)]
        ))
    }
    
    /// Get all available tracks for enrollment, including groups without records (virtual tracks).
    /// Returns all groups that are tracks (not explicitly disabled) with their effective settings.
    /// This includes both actual GroupTrack records and virtual tracks for groups without records.
    static func getAllAvailableTracks(
        from lessons: [Lesson],
        modelContext: ModelContext
    ) throws -> [AvailableTrack] {
        // PERFORMANCE: Fetch all GroupTracks ONCE to avoid N+1 queries in the loop below
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let tracksByKey: [String: GroupTrack] = Dictionary(
            allTracks.map { track in
                let key = "\(track.subject.trimmed().lowercased())|\(track.group.trimmed().lowercased())"
                return (key, track)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // In-memory helper: check if a group is a track (using cached data)
        func isTrackCached(subject: String, group: String) -> Bool {
            let key = "\(subject.trimmed().lowercased())|\(group.trimmed().lowercased())"
            if let track = tracksByKey[key] {
                return !track.isExplicitlyDisabled
            }
            // No record exists = default behavior = is a track
            return true
        }

        // In-memory helper: get effective settings (using cached data)
        func getSettingsCached(subject: String, group: String) -> (isSequential: Bool, isExplicitlyDisabled: Bool) {
            let key = "\(subject.trimmed().lowercased())|\(group.trimmed().lowercased())"
            if let track = tracksByKey[key] {
                return (isSequential: track.isSequential, isExplicitlyDisabled: track.isExplicitlyDisabled)
            }
            // Default: sequential, not disabled
            return (isSequential: true, isExplicitlyDisabled: false)
        }

        // Get all unique (subject, group) combinations from lessons
        // Use a dictionary to deduplicate (subject, group) pairs
        var uniqueGroupsDict: [String: (subject: String, group: String)] = [:]
        for lesson in lessons {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            guard !subject.isEmpty && !group.isEmpty else { continue }
            let key = "\(subject)|\(group)"
            if uniqueGroupsDict[key] == nil {
                uniqueGroupsDict[key] = (subject: subject, group: group)
            }
        }
        let uniqueGroups = Array(uniqueGroupsDict.values)

        // Build list of available tracks using cached lookups (O(1) per iteration)
        var availableTracks: [AvailableTrack] = []

        for (subject, group) in uniqueGroups {
            // Check if this group is a track (all groups are tracks by default unless explicitly disabled)
            guard isTrackCached(subject: subject, group: group) else {
                continue // Skip explicitly disabled groups
            }

            // Get effective settings (sequential by default if no record exists)
            let settings = getSettingsCached(subject: subject, group: group)
            availableTracks.append(AvailableTrack(subject: subject, group: group, isSequential: settings.isSequential))
        }

        // Sort by subject, then group
        return availableTracks.sorted { lhs, rhs in
            if lhs.subject != rhs.subject {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
        }
    }
    
    /// Get all lessons for a group track, sorted by orderInGroup
    static func getLessonsForTrack(
        track: GroupTrack,
        allLessons: [Lesson]
    ) -> [Lesson] {
        return allLessons
            .filter { lesson in
                lesson.subject.trimmed().caseInsensitiveCompare(track.subject.trimmed()) == .orderedSame &&
                lesson.group.trimmed().caseInsensitiveCompare(track.group.trimmed()) == .orderedSame
            }
            .sorted { lhs, rhs in
                if track.isSequential {
                    // Sequential: respect orderInGroup
                    if lhs.orderInGroup != rhs.orderInGroup {
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                }
                // Fallback to name for stable ordering
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
    
    // MARK: - Track Object Management (UUID-based Track model)
    
    /// Find or create a Track object for the given subject and group.
    /// This creates Track and TrackStep objects that can be used for enrollment and history linking.
    /// - Parameters:
    ///   - subject: The subject name
    ///   - group: The group name
    ///   - modelContext: The model context for database operations
    /// - Returns: The Track object (existing or newly created)
    static func getOrCreateTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> Track {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        
        // Check if this group should be a track
        guard isTrack(subject: trimmedSubject, group: trimmedGroup, modelContext: modelContext) else {
            throw NSError(
                domain: "GroupTrackService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Group is explicitly disabled as a track"]
            )
        }
        
        // Fetch all Tracks to find existing one by title
        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        let allTracks = try modelContext.fetch(FetchDescriptor<Track>())
        
        if let existingTrack = allTracks.first(where: { $0.title.trimmed() == trackTitle }) {
            // Track exists - ensure TrackSteps are up to date
            try ensureTrackSteps(
                for: existingTrack, subject: trimmedSubject,
                group: trimmedGroup, modelContext: modelContext
            )
            return existingTrack
        }
        
        // Create new Track
        let newTrack = Track(
            title: trackTitle,
            createdAt: Date()
        )
        modelContext.insert(newTrack)
        
        // Create TrackSteps for all lessons in this group
        try ensureTrackSteps(for: newTrack, subject: trimmedSubject, group: trimmedGroup, modelContext: modelContext)
        
        return newTrack
    }
    
    /// Ensure TrackSteps exist for all lessons in a subject/group combination.
    /// This adds missing steps and removes steps for lessons that no longer exist.
    private static func ensureTrackSteps(
        for track: Track,
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws {
        // Fetch all lessons for this subject/group
        let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
        let matchingLessons = allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        
        // Get existing steps
        let allSteps = try modelContext.fetch(FetchDescriptor<TrackStep>())
        let existingSteps = allSteps.filter { step in
            step.track?.id == track.id
        }
        
        // Build map of existing steps by lesson ID
        var existingStepsByLessonID: [UUID: TrackStep] = [:]
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID {
                existingStepsByLessonID[lessonID] = step
            }
        }
        
        // Create or update steps for each lesson
        var steps: [TrackStep] = []
        for (index, lesson) in matchingLessons.enumerated() {
            if let existingStep = existingStepsByLessonID[lesson.id] {
                // Update orderIndex if needed
                existingStep.orderIndex = index
                existingStep.track = track
                steps.append(existingStep)
            } else {
                // Create new step
                let newStep = TrackStep(
                    track: track,
                    orderIndex: index,
                    lessonTemplateID: lesson.id,
                    createdAt: Date()
                )
                modelContext.insert(newStep)
                steps.append(newStep)
            }
        }
        
        // Remove steps for lessons that no longer exist
        let existingLessonIDs = Set(matchingLessons.map { $0.id })
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID, !existingLessonIDs.contains(lessonID) {
                modelContext.delete(step)
            }
        }
        
        // Update track.steps relationship
        track.steps = steps
    }
    
    /// Get Track object for a subject/group combination, if it exists.
    static func getTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> Track? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        
        let allTracks = try modelContext.fetch(FetchDescriptor<Track>())
        return allTracks.first(where: { $0.title.trimmed() == trackTitle })
    }
    
    /// Automatically enroll students in a track if the lesson belongs to a track.
    /// Called when a lesson is scheduled or presented.
    /// Now uses Track objects with UUID IDs instead of subject|group strings.
    /// - Parameters:
    ///   - lesson: The lesson that was scheduled/presented
    ///   - studentIDs: Array of student UUID strings to enroll
    ///   - modelContext: The model context for database operations
    ///   - saveCoordinator: Optional save coordinator for error handling (uses silent fallback if nil)
    @MainActor static func autoEnrollInTrackIfNeeded(
        lesson: Lesson,
        studentIDs: [String],
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        // Check if this lesson belongs to a track (using new default behavior)
        guard isTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext) else {
            // Lesson doesn't belong to a track (explicitly disabled), nothing to do
            return
        }
        
        // Find or create Track object
        let track: Track
        do {
            track = try getOrCreateTrack(
                subject: lesson.subject,
                group: lesson.group,
                modelContext: modelContext
            )
        } catch {
            logger.warning("Failed to get or create track during auto-enroll: \(error.localizedDescription)")
            return
        }
        
        let trackID = track.id.uuidString
        
        // Fetch all existing enrollments for these students
        let allEnrollments = safeFetch(
            FetchDescriptor<StudentTrackEnrollment>(),
            modelContext: modelContext,
            context: "autoEnrollInTrackIfNeeded"
        )
        
        // Enroll each student if not already enrolled
        for studentID in studentIDs {
            // Check if enrollment already exists (by Track UUID)
            let existingEnrollment = allEnrollments.first { enrollment in
                enrollment.studentID == studentID && enrollment.trackID == trackID
            }
            
            if let existing = existingEnrollment {
                // Reactivate if inactive
                if !existing.isActive {
                    existing.isActive = true
                    if existing.startedAt == nil {
                        existing.startedAt = Date()
                    }
                }
            } else {
                // Create new enrollment with Track UUID
                let newEnrollment = StudentTrackEnrollment(
                    studentID: studentID,
                    trackID: trackID,
                    startedAt: Date(),
                    isActive: true
                )
                modelContext.insert(newEnrollment)
            }
        }
        
        // Save changes
        if let coordinator = saveCoordinator {
            coordinator.save(modelContext, reason: "Auto-enrolling in track")
        } else {
            safeSave(modelContext: modelContext, context: "autoEnrollInTrackIfNeeded")
        }
    }

    // MARK: - Track Completion

    /// Check if a track is complete for a student and mark the enrollment as inactive if so.
    /// A track is complete when all lessons in the track have been mastered by the student.
    /// - Parameters:
    ///   - lesson: The lesson that was just mastered (used to find the track)
    ///   - studentID: The student's UUID string
    ///   - modelContext: The model context for database operations
    ///   - saveCoordinator: Optional save coordinator for error handling (uses silent fallback if nil)
    static func checkAndCompleteTrackIfNeeded(
        lesson: Lesson,
        studentID: String,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        // Check if this lesson belongs to a track
        guard isTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext) else {
            return
        }

        // Get the Track object
        let track: Track
        do {
            guard let fetchedTrack = try getTrack(
                subject: lesson.subject, group: lesson.group,
                modelContext: modelContext
            ) else {
                return
            }
            track = fetchedTrack
        } catch {
            logger.warning("Failed to get track for completion check: \(error.localizedDescription)")
            return
        }

        // Get all lessons in this track
        let allLessons = safeFetch(
            FetchDescriptor<Lesson>(), modelContext: modelContext,
            context: "checkAndCompleteTrackIfNeeded"
        )
        let trackLessons = allLessons.filter { l in
            l.subject.trimmed().caseInsensitiveCompare(lesson.subject.trimmed()) == .orderedSame &&
            l.group.trimmed().caseInsensitiveCompare(lesson.group.trimmed()) == .orderedSame
        }

        guard !trackLessons.isEmpty else { return }

        // Get all LessonPresentation records for this student
        let allLessonPresentations = safeFetch(
            FetchDescriptor<LessonPresentation>(),
            modelContext: modelContext,
            context: "checkAndCompleteTrackIfNeeded"
        )
        let studentPresentations = allLessonPresentations.filter { $0.studentID == studentID }

        // Check if all lessons in the track are mastered
        let trackLessonIDs = Set(trackLessons.map { $0.id.uuidString })
        let proficientLessonIDs = Set(studentPresentations
            .filter { $0.state == .proficient && trackLessonIDs.contains($0.lessonID) }
            .map { $0.lessonID })

        let allProficient = trackLessonIDs.isSubset(of: proficientLessonIDs)

        guard allProficient else { return }

        // All lessons mastered - mark enrollment as inactive (completed)
        let trackID = track.id.uuidString
        let allEnrollments = safeFetch(
            FetchDescriptor<StudentTrackEnrollment>(),
            modelContext: modelContext,
            context: "checkAndCompleteTrackIfNeeded"
        )

        if let enrollment = allEnrollments.first(where: {
            $0.studentID == studentID && $0.trackID == trackID && $0.isActive
        }) {
            enrollment.isActive = false
            if let coordinator = saveCoordinator {
                coordinator.save(modelContext, reason: "Completing track enrollment")
            } else {
                safeSave(modelContext: modelContext, context: "checkAndCompleteTrackIfNeeded")
            }
        }
    }
}
