#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("TrackProgressResolver Tests")
struct TrackProgressResolverTests {

    // MARK: - Test Helpers

    private func makeTrackStep(id: UUID = UUID(), orderIndex: Int, lessonTemplateID: UUID? = nil) -> TrackStep {
        return TrackStep(id: id, track: nil, orderIndex: orderIndex, lessonTemplateID: lessonTemplateID)
    }

    private func makeTrack(title: String = "Test Track", steps: [TrackStep]) -> Track {
        let track = Track(title: title)
        track.steps = steps
        return track
    }

    private func makeLessonPresentation(
        studentID: String,
        lessonID: String,
        trackStepID: String? = nil,
        state: LessonPresentationState = .presented,
        masteredAt: Date? = nil
    ) -> LessonPresentation {
        return LessonPresentation(
            studentID: studentID,
            lessonID: lessonID,
            trackStepID: trackStepID,
            state: state,
            masteredAt: masteredAt
        )
    }

    // MARK: - totalSteps Tests

    @Test("totalSteps returns correct count for empty track")
    func totalStepsEmpty() {
        let track = makeTrack(steps: [])

        let result = TrackProgressResolver.totalSteps(track: track)

        #expect(result == 0)
    }

    @Test("totalSteps returns correct count for single step")
    func totalStepsSingle() {
        let step = makeTrackStep(orderIndex: 0)
        let track = makeTrack(steps: [step])

        let result = TrackProgressResolver.totalSteps(track: track)

        #expect(result == 1)
    }

    @Test("totalSteps returns correct count for multiple steps")
    func totalStepsMultiple() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
            makeTrackStep(orderIndex: 3),
        ]
        let track = makeTrack(steps: steps)

        let result = TrackProgressResolver.totalSteps(track: track)

        #expect(result == 4)
    }

    @Test("totalSteps handles unsorted steps")
    func totalStepsUnsorted() {
        let steps = [
            makeTrackStep(orderIndex: 3),
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 2),
            makeTrackStep(orderIndex: 1),
        ]
        let track = makeTrack(steps: steps)

        let result = TrackProgressResolver.totalSteps(track: track)

        #expect(result == 4)
    }

    // MARK: - masteredCount Tests

    @Test("masteredCount returns 0 for empty track")
    func masteredCountEmpty() {
        let track = makeTrack(steps: [])
        let presentations: [LessonPresentation] = []

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == 0)
    }

    @Test("masteredCount returns 0 when no presentations")
    func masteredCountNoPresentations() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0)
        let track = makeTrack(steps: [step])
        let presentations: [LessonPresentation] = []

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == 0)
    }

    @Test("masteredCount counts step with masteredAt timestamp")
    func masteredCountWithMasteredAt() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0)
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student1",
            lessonID: "lesson1",
            trackStepID: stepID.uuidString,
            masteredAt: Date()
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 1)
    }

    @Test("masteredCount counts step with mastered state")
    func masteredCountWithMasteredState() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0)
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student1",
            lessonID: "lesson1",
            trackStepID: stepID.uuidString,
            state: .mastered,
            masteredAt: nil
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 1)
    }

    @Test("masteredCount matches by trackStepID")
    func masteredCountMatchByTrackStepID() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0, lessonTemplateID: UUID())
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student1",
            lessonID: "differentLesson",
            trackStepID: stepID.uuidString,
            state: .mastered
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 1)
    }

    @Test("masteredCount matches by lessonTemplateID")
    func masteredCountMatchByLessonTemplateID() {
        let lessonID = UUID()
        let step = makeTrackStep(orderIndex: 0, lessonTemplateID: lessonID)
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student1",
            lessonID: lessonID.uuidString,
            trackStepID: nil,
            state: .mastered
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 1)
    }

    @Test("masteredCount ignores presentations without mastery")
    func masteredCountIgnoresNonMastered() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0)
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student1",
            lessonID: "lesson1",
            trackStepID: stepID.uuidString,
            state: .presented,
            masteredAt: nil
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 0)
    }

    @Test("masteredCount ignores presentations for different student")
    func masteredCountIgnoresDifferentStudent() {
        let stepID = UUID()
        let step = makeTrackStep(id: stepID, orderIndex: 0)
        let track = makeTrack(steps: [step])

        let presentation = makeLessonPresentation(
            studentID: "student2",
            lessonID: "lesson1",
            trackStepID: stepID.uuidString,
            state: .mastered
        )

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: [presentation])

        #expect(result == 0)
    }

    @Test("masteredCount with multiple mastered steps")
    func masteredCountMultiple() {
        let step1ID = UUID()
        let step2ID = UUID()
        let step3ID = UUID()

        let steps = [
            makeTrackStep(id: step1ID, orderIndex: 0),
            makeTrackStep(id: step2ID, orderIndex: 1),
            makeTrackStep(id: step3ID, orderIndex: 2),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: step1ID.uuidString, state: .mastered),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson2", trackStepID: step2ID.uuidString, state: .mastered),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson3", trackStepID: step3ID.uuidString, state: .presented), // Not mastered
        ]

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == 2)
    }

    @Test("masteredCount with partial progress")
    func masteredCountPartialProgress() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
            makeTrackStep(orderIndex: 3),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: steps[0].id.uuidString, masteredAt: Date()),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson2", trackStepID: steps[1].id.uuidString, state: .mastered),
        ]

        let result = TrackProgressResolver.masteredCount(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == 2)
    }

    // MARK: - currentStep Tests

    @Test("currentStep returns nil for empty track")
    func currentStepEmpty() {
        let track = makeTrack(steps: [])
        let presentations: [LessonPresentation] = []

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == nil)
    }

    @Test("currentStep returns first step when no progress")
    func currentStepNoProgress() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
        ]
        let track = makeTrack(steps: steps)
        let presentations: [LessonPresentation] = []

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result?.id == steps[0].id)
    }

    @Test("currentStep returns second step when first is mastered")
    func currentStepFirstMastered() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: steps[0].id.uuidString, state: .mastered),
        ]

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result?.id == steps[1].id)
    }

    @Test("currentStep returns third step when first two are mastered")
    func currentStepTwoMastered() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
            makeTrackStep(orderIndex: 3),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: steps[0].id.uuidString, masteredAt: Date()),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson2", trackStepID: steps[1].id.uuidString, state: .mastered),
        ]

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result?.id == steps[2].id)
    }

    @Test("currentStep returns nil when all steps mastered")
    func currentStepAllMastered() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: steps[0].id.uuidString, state: .mastered),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson2", trackStepID: steps[1].id.uuidString, state: .mastered),
            makeLessonPresentation(studentID: "student1", lessonID: "lesson3", trackStepID: steps[2].id.uuidString, masteredAt: Date()),
        ]

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        #expect(result == nil)
    }

    @Test("currentStep handles unsorted steps correctly")
    func currentStepUnsortedSteps() {
        let steps = [
            makeTrackStep(orderIndex: 2),
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student1", lessonID: "lesson1", trackStepID: steps[1].id.uuidString, state: .mastered), // orderIndex 0
        ]

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        // Should return the step with orderIndex 1 (steps[2])
        #expect(result?.orderIndex == 1)
    }

    @Test("currentStep ignores presentations for other students")
    func currentStepIgnoresOtherStudents() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
        ]
        let track = makeTrack(steps: steps)

        let presentations = [
            makeLessonPresentation(studentID: "student2", lessonID: "lesson1", trackStepID: steps[0].id.uuidString, state: .mastered),
        ]

        let result = TrackProgressResolver.currentStep(track: track, studentID: "student1", lessonPresentations: presentations)

        // student1 has no progress, so should return first step
        #expect(result?.id == steps[0].id)
    }

    // MARK: - Integration Tests

    @Test("Complete workflow: track progress from start to finish")
    func completeWorkflow() {
        let steps = [
            makeTrackStep(orderIndex: 0),
            makeTrackStep(orderIndex: 1),
            makeTrackStep(orderIndex: 2),
        ]
        let track = makeTrack(title: "Math Track", steps: steps)
        let studentID = "student1"

        // Initial state: no progress
        var presentations: [LessonPresentation] = []
        #expect(TrackProgressResolver.totalSteps(track: track) == 3)
        #expect(TrackProgressResolver.masteredCount(track: track, studentID: studentID, lessonPresentations: presentations) == 0)
        #expect(TrackProgressResolver.currentStep(track: track, studentID: studentID, lessonPresentations: presentations)?.orderIndex == 0)

        // Student masters first step
        presentations.append(makeLessonPresentation(studentID: studentID, lessonID: "lesson1", trackStepID: steps[0].id.uuidString, state: .mastered))
        #expect(TrackProgressResolver.masteredCount(track: track, studentID: studentID, lessonPresentations: presentations) == 1)
        #expect(TrackProgressResolver.currentStep(track: track, studentID: studentID, lessonPresentations: presentations)?.orderIndex == 1)

        // Student masters second step
        presentations.append(makeLessonPresentation(studentID: studentID, lessonID: "lesson2", trackStepID: steps[1].id.uuidString, masteredAt: Date()))
        #expect(TrackProgressResolver.masteredCount(track: track, studentID: studentID, lessonPresentations: presentations) == 2)
        #expect(TrackProgressResolver.currentStep(track: track, studentID: studentID, lessonPresentations: presentations)?.orderIndex == 2)

        // Student masters final step
        presentations.append(makeLessonPresentation(studentID: studentID, lessonID: "lesson3", trackStepID: steps[2].id.uuidString, state: .mastered))
        #expect(TrackProgressResolver.masteredCount(track: track, studentID: studentID, lessonPresentations: presentations) == 3)
        #expect(TrackProgressResolver.currentStep(track: track, studentID: studentID, lessonPresentations: presentations) == nil) // Completed!
    }
}

#endif
