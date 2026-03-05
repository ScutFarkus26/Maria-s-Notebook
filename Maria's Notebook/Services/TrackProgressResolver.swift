import Foundation

/// Helper struct for resolving track progress without SwiftData fetches.
/// All operations work on passed-in arrays.
struct TrackProgressResolver {
    /// Returns the total number of steps in the track.
    static func totalSteps(track: Track) -> Int {
        let steps = (track.steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
        return steps.count
    }
    
    /// Returns the count of mastered steps for a given student.
    /// A step is mastered if there exists a LessonPresentation where:
    /// - studentID matches
    /// - (masteredAt != nil OR state == .proficient)
    /// - (trackStepID matches step.id OR lessonID matches step.lessonTemplateID)
    static func proficientCount(track: Track, studentID: String, lessonPresentations: [LessonPresentation]) -> Int {
        let steps = (track.steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
        
        return steps.filter { step in
            isStepProficient(step: step, studentID: studentID, lessonPresentations: lessonPresentations)
        }.count
    }
    
    /// Returns the first unmastered step in the track, or nil if all steps are mastered.
    static func currentStep(track: Track, studentID: String, lessonPresentations: [LessonPresentation]) -> TrackStep? {
        let steps = (track.steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
        
        return steps.first { step in
            !isStepProficient(step: step, studentID: studentID, lessonPresentations: lessonPresentations)
        }
    }
    
    /// Helper function to determine if a step is mastered.
    private static func isStepProficient(step: TrackStep, studentID: String, lessonPresentations: [LessonPresentation]) -> Bool {
        return lessonPresentations.contains { lp in
            // Check student ID matches
            guard lp.studentID == studentID else { return false }
            
            // Check if mastered (either masteredAt is set or state is mastered)
            guard lp.masteredAt != nil || lp.state == .proficient else { return false }
            
            // Check if this presentation matches the step
            // Either by trackStepID or by lessonTemplateID
            let matchesByTrackStepID = lp.trackStepID != nil && lp.trackStepID == step.id.uuidString
            let matchesByLessonID = step.lessonTemplateID != nil && lp.lessonID == step.lessonTemplateID!.uuidString
            
            return matchesByTrackStepID || matchesByLessonID
        }
    }
}
