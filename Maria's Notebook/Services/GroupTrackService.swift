import Foundation
import SwiftData

/// Service for managing group-based tracks
struct GroupTrackService {
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
    ) throws -> [(subject: String, group: String, isSequential: Bool)] {
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
        
        // Build list of available tracks
        var availableTracks: [(subject: String, group: String, isSequential: Bool)] = []
        
        for (subject, group) in uniqueGroups {
            // Check if this group is a track (all groups are tracks by default unless explicitly disabled)
            guard isTrack(subject: subject, group: group, modelContext: modelContext) else {
                continue // Skip explicitly disabled groups
            }
            
            // Get effective settings (sequential by default if no record exists)
            let settings = try getEffectiveTrackSettings(subject: subject, group: group, modelContext: modelContext)
            availableTracks.append((subject: subject, group: group, isSequential: settings.isSequential))
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
    
    /// Automatically enroll students in a track if the lesson belongs to a track.
    /// Called when a lesson is scheduled or presented.
    /// - Parameters:
    ///   - lesson: The lesson that was scheduled/presented
    ///   - studentIDs: Array of student UUID strings to enroll
    ///   - modelContext: The model context for database operations
    static func autoEnrollInTrackIfNeeded(
        lesson: Lesson,
        studentIDs: [String],
        modelContext: ModelContext
    ) {
        // Check if this lesson belongs to a track (using new default behavior)
        guard isTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext) else {
            // Lesson doesn't belong to a track (explicitly disabled), nothing to do
            return
        }
        
        let trackID = "\(lesson.subject.trimmed())|\(lesson.group.trimmed())"
        
        // Fetch all existing enrollments for these students
        let allEnrollments = (try? modelContext.fetch(FetchDescriptor<StudentTrackEnrollment>())) ?? []
        
        // Enroll each student if not already enrolled
        for studentID in studentIDs {
            // Check if enrollment already exists
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
                // Create new enrollment
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
        try? modelContext.save()
    }
}
