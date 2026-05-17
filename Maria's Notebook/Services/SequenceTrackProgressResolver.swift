import Foundation

/// Helper struct for resolving sequence-based track progress without SwiftData fetches.
/// All operations work on passed-in arrays.
@MainActor
struct SequenceTrackProgressResolver {
    /// Returns the total number of lessons in the sequence track.
    static func totalLessons(track: CDSequenceTrackEntity, lessons: [CDLesson]) -> Int {
        return SequenceTrackService.getLessonsForTrack(track: track, allLessons: lessons).count
    }
    
    /// Returns the count of mastered lessons for a given student in a sequence track.
    /// A lesson is mastered if there exists a CDLessonPresentation where:
    /// - studentID matches
    /// - (masteredAt != nil OR state == .proficient)
    /// - lessonID matches the lesson's ID
    static func proficientCount(
        track: CDSequenceTrackEntity,
        studentID: String,
        lessons: [CDLesson],
        lessonPresentations: [CDLessonPresentation]
    ) -> Int {
        let trackLessons = SequenceTrackService.getLessonsForTrack(track: track, allLessons: lessons)
        
        return trackLessons.filter { lesson in
            isLessonProficient(lesson: lesson, studentID: studentID, lessonPresentations: lessonPresentations)
        }.count
    }
    
    /// Returns the first unmastered lesson in the track (for sequential tracks),
    /// or nil if all are mastered or track is unordered.
    static func currentLesson(
        track: CDSequenceTrackEntity,
        studentID: String,
        lessons: [CDLesson],
        lessonPresentations: [CDLessonPresentation]
    ) -> CDLesson? {
        guard track.isSequential else { return nil } // No "current" lesson for unordered tracks
        
        let trackLessons = SequenceTrackService.getLessonsForTrack(track: track, allLessons: lessons)
        
        return trackLessons.first { lesson in
            !isLessonProficient(lesson: lesson, studentID: studentID, lessonPresentations: lessonPresentations)
        }
    }
    
    /// Helper function to determine if a lesson is mastered.
    private static func isLessonProficient(
        lesson: CDLesson, studentID: String,
        lessonPresentations: [CDLessonPresentation]
    ) -> Bool {
        let lessonIDStr = lesson.id?.uuidString ?? ""
        return lessonPresentations.contains { lp in
            // Check student ID matches
            guard lp.studentID == studentID else { return false }
            
            // Check if mastered (either masteredAt is set or state is mastered)
            guard lp.masteredAt != nil || lp.state == .proficient else { return false }
            
            // Check if this presentation matches the lesson
            return lp.lessonID == lessonIDStr
        }
    }
}
