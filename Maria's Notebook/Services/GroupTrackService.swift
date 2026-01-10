import Foundation
import SwiftData

/// Service for managing group-based tracks
struct GroupTrackService {
    /// Get or create a GroupTrack for the given subject and group
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
        
        // Create new GroupTrack
        let newTrack = GroupTrack(
            subject: trimmedSubject,
            group: trimmedGroup,
            isSequential: true // Default to sequential
        )
        modelContext.insert(newTrack)
        return newTrack
    }
    
    /// Get GroupTrack for subject and group, or nil if not found
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
    
    /// Check if a group is marked as a track
    static func isTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) -> Bool {
        do {
            return try getGroupTrack(subject: subject, group: group, modelContext: modelContext) != nil
        } catch {
            return false
        }
    }
    
    /// Remove track designation from a group
    static func removeTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws {
        if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
            modelContext.delete(track)
        }
    }
    
    /// Get all group tracks
    static func getAllGroupTracks(modelContext: ModelContext) throws -> [GroupTrack] {
        return try modelContext.fetch(FetchDescriptor<GroupTrack>(
            sortBy: [SortDescriptor(\.subject), SortDescriptor(\.group)]
        ))
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
        // Check if this lesson belongs to a track
        guard let track = try? getGroupTrack(
            subject: lesson.subject,
            group: lesson.group,
            modelContext: modelContext
        ) else {
            // Lesson doesn't belong to a track, nothing to do
            return
        }
        
        // Fetch all existing enrollments for these students
        let allEnrollments = (try? modelContext.fetch(FetchDescriptor<StudentTrackEnrollment>())) ?? []
        let trackID = "\(track.subject)|\(track.group)"
        
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
