import Foundation

/// Helper struct for resolving group-based track progress without SwiftData fetches.
/// All operations work on passed-in arrays.
@MainActor
struct GroupTrackProgressResolver {
    /// Returns the total number of lessons in the group track.
    static func totalLessons(track: GroupTrack, lessons: [Lesson]) -> Int {
        return GroupTrackService.getLessonsForTrack(track: track, allLessons: lessons).count
    }
    
    /// Returns the count of mastered lessons for a given student in a group track.
    /// A lesson is mastered if there exists a LessonPresentation where:
    /// - studentID matches
    /// - (masteredAt != nil OR state == .mastered)
    /// - lessonID matches the lesson's ID
    static func masteredCount(
        track: GroupTrack,
        studentID: String,
        lessons: [Lesson],
        lessonPresentations: [LessonPresentation]
    ) -> Int {
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: lessons)
        
        return trackLessons.filter { lesson in
            isLessonMastered(lesson: lesson, studentID: studentID, lessonPresentations: lessonPresentations)
        }.count
    }
    
    /// Returns the first unmastered lesson in the track (for sequential tracks), or nil if all are mastered or track is unordered.
    static func currentLesson(
        track: GroupTrack,
        studentID: String,
        lessons: [Lesson],
        lessonPresentations: [LessonPresentation]
    ) -> Lesson? {
        guard track.isSequential else { return nil } // No "current" lesson for unordered tracks
        
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: lessons)
        
        return trackLessons.first { lesson in
            !isLessonMastered(lesson: lesson, studentID: studentID, lessonPresentations: lessonPresentations)
        }
    }
    
    /// Helper function to determine if a lesson is mastered.
    private static func isLessonMastered(lesson: Lesson, studentID: String, lessonPresentations: [LessonPresentation]) -> Bool {
        let lessonIDStr = lesson.id.uuidString
        return lessonPresentations.contains { lp in
            // Check student ID matches
            guard lp.studentID == studentID else { return false }
            
            // Check if mastered (either masteredAt is set or state is mastered)
            guard lp.masteredAt != nil || lp.state == .mastered else { return false }
            
            // Check if this presentation matches the lesson
            return lp.lessonID == lessonIDStr
        }
    }
}
