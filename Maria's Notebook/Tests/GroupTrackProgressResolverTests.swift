#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Total Lessons Tests

@Suite("GroupTrackProgressResolver Total Lessons Tests")
@MainActor
struct GroupTrackProgressResolverTotalLessonsTests {

    @Test("totalLessons returns zero for empty track")
    func totalLessonsReturnsZeroForEmptyTrack() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lessons: [Lesson] = []

        let total = GroupTrackProgressResolver.totalLessons(track: track, lessons: lessons)

        #expect(total == 0)
    }

    @Test("totalLessons returns count for matching lessons")
    func totalLessonsReturnsCountForMatching() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lessons = [
            makeTestLesson(name: "Addition", subject: "Math", group: "Operations"),
            makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations"),
            makeTestLesson(name: "Reading", subject: "Language", group: "Literacy"),
        ]

        let total = GroupTrackProgressResolver.totalLessons(track: track, lessons: lessons)

        #expect(total == 2)
    }

    @Test("totalLessons filters by subject and group")
    func totalLessonsFiltersBySubjectAndGroup() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lessons = [
            makeTestLesson(name: "Addition", subject: "Math", group: "Operations"),
            makeTestLesson(name: "Geometry", subject: "Math", group: "Shapes"),
            makeTestLesson(name: "Reading", subject: "Language", group: "Operations"), // Wrong subject
        ]

        let total = GroupTrackProgressResolver.totalLessons(track: track, lessons: lessons)

        #expect(total == 1)
    }
}

// MARK: - Mastered Count Tests

@Suite("GroupTrackProgressResolver Mastered Count Tests")
@MainActor
struct GroupTrackProgressResolverMasteredCountTests {

    @Test("masteredCount returns zero when no presentations")
    func masteredCountReturnsZeroWhenNoPresentations() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: UUID().uuidString,
            lessons: [lesson],
            lessonPresentations: []
        )

        #expect(count == 0)
    }

    @Test("masteredCount counts mastered lessons")
    func masteredCountCountsMasteredLessons() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: studentID,
            lessonID: lesson.id.uuidString,
            state: .mastered
        )

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [lesson],
            lessonPresentations: [presentation]
        )

        #expect(count == 1)
    }

    @Test("masteredCount recognizes masteredAt as mastered")
    func masteredCountRecognizesMasteredAt() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: studentID,
            lessonID: lesson.id.uuidString,
            state: .presented,
            masteredAt: Date()
        )

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [lesson],
            lessonPresentations: [presentation]
        )

        #expect(count == 1)
    }

    @Test("masteredCount ignores presentations for other students")
    func masteredCountIgnoresOtherStudents() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let otherStudentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: otherStudentID,
            lessonID: lesson.id.uuidString,
            state: .mastered
        )

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [lesson],
            lessonPresentations: [presentation]
        )

        #expect(count == 0)
    }

    @Test("masteredCount ignores non-mastered presentations")
    func masteredCountIgnoresNonMastered() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: studentID,
            lessonID: lesson.id.uuidString,
            state: .presented
        )

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [lesson],
            lessonPresentations: [presentation]
        )

        #expect(count == 0)
    }

    @Test("masteredCount with multiple mastered lessons")
    func masteredCountWithMultipleMastered() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        let lesson3 = makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let presentations = [
            LessonPresentation(studentID: studentID, lessonID: lesson1.id.uuidString, state: .mastered),
            LessonPresentation(studentID: studentID, lessonID: lesson2.id.uuidString, state: .mastered),
            LessonPresentation(studentID: studentID, lessonID: lesson3.id.uuidString, state: .presented),
        ]

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [lesson1, lesson2, lesson3],
            lessonPresentations: presentations
        )

        #expect(count == 2)
    }

    @Test("masteredCount only counts lessons in track")
    func masteredCountOnlyCountsTrackLessons() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        let trackLesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let otherLesson = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")

        let studentID = UUID().uuidString
        let presentations = [
            LessonPresentation(studentID: studentID, lessonID: trackLesson.id.uuidString, state: .mastered),
            LessonPresentation(studentID: studentID, lessonID: otherLesson.id.uuidString, state: .mastered),
        ]

        let count = GroupTrackProgressResolver.masteredCount(
            track: track,
            studentID: studentID,
            lessons: [trackLesson, otherLesson],
            lessonPresentations: presentations
        )

        // Only trackLesson should count
        #expect(count == 1)
    }
}

// MARK: - Current Lesson Tests

@Suite("GroupTrackProgressResolver Current Lesson Tests")
@MainActor
struct GroupTrackProgressResolverCurrentLessonTests {

    @Test("currentLesson returns nil for non-sequential track")
    func currentLessonReturnsNilForNonSequential() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = false
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let current = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: UUID().uuidString,
            lessons: [lesson],
            lessonPresentations: []
        )

        #expect(current == nil)
    }

    @Test("currentLesson returns first lesson for sequential track with no progress")
    func currentLessonReturnsFirstForSequentialNoProgress() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true
        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2)

        let current = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: UUID().uuidString,
            lessons: [lesson1, lesson2],
            lessonPresentations: []
        )

        #expect(current?.id == lesson1.id)
    }

    @Test("currentLesson returns second lesson when first is mastered")
    func currentLessonReturnsSecondWhenFirstMastered() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true
        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2)

        let studentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: studentID,
            lessonID: lesson1.id.uuidString,
            state: .mastered
        )

        let current = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: studentID,
            lessons: [lesson1, lesson2],
            lessonPresentations: [presentation]
        )

        #expect(current?.id == lesson2.id)
    }

    @Test("currentLesson returns nil when all lessons mastered")
    func currentLessonReturnsNilWhenAllMastered() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")

        let studentID = UUID().uuidString
        let presentation = LessonPresentation(
            studentID: studentID,
            lessonID: lesson.id.uuidString,
            state: .mastered
        )

        let current = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: studentID,
            lessons: [lesson],
            lessonPresentations: [presentation]
        )

        #expect(current == nil)
    }

    @Test("currentLesson returns nil for empty track")
    func currentLessonReturnsNilForEmptyTrack() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true

        let current = GroupTrackProgressResolver.currentLesson(
            track: track,
            studentID: UUID().uuidString,
            lessons: [],
            lessonPresentations: []
        )

        #expect(current == nil)
    }
}

// MARK: - Integration Tests

@Suite("GroupTrackProgressResolver Integration Tests")
@MainActor
struct GroupTrackProgressResolverIntegrationTests {

    @Test("Complete workflow: sequential track progress")
    func completeWorkflowSequentialTrack() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2)
        let lesson3 = makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations", orderInGroup: 3)
        let lessons = [lesson1, lesson2, lesson3]

        let studentID = UUID().uuidString
        var presentations: [LessonPresentation] = []

        // Initial state
        #expect(GroupTrackProgressResolver.totalLessons(track: track, lessons: lessons) == 3)
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations) == 0)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations)?.id == lesson1.id)

        // Master first lesson
        presentations.append(LessonPresentation(studentID: studentID, lessonID: lesson1.id.uuidString, state: .mastered))
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations) == 1)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations)?.id == lesson2.id)

        // Master second lesson
        presentations.append(LessonPresentation(studentID: studentID, lessonID: lesson2.id.uuidString, masteredAt: Date()))
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations) == 2)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations)?.id == lesson3.id)

        // Master final lesson
        presentations.append(LessonPresentation(studentID: studentID, lessonID: lesson3.id.uuidString, state: .mastered))
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations) == 3)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: studentID, lessons: lessons, lessonPresentations: presentations) == nil)
    }

    @Test("Multiple students with independent progress")
    func multipleStudentsIndependentProgress() {
        let track = GroupTrack(subject: "Math", group: "Operations")
        track.isSequential = true

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2)
        let lessons = [lesson1, lesson2]

        let student1ID = UUID().uuidString
        let student2ID = UUID().uuidString

        // Student 1 has mastered first lesson
        // Student 2 has mastered both lessons
        let presentations = [
            LessonPresentation(studentID: student1ID, lessonID: lesson1.id.uuidString, state: .mastered),
            LessonPresentation(studentID: student2ID, lessonID: lesson1.id.uuidString, state: .mastered),
            LessonPresentation(studentID: student2ID, lessonID: lesson2.id.uuidString, state: .mastered),
        ]

        // Student 1: 1 mastered, current is lesson 2
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: student1ID, lessons: lessons, lessonPresentations: presentations) == 1)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: student1ID, lessons: lessons, lessonPresentations: presentations)?.id == lesson2.id)

        // Student 2: 2 mastered, track complete
        #expect(GroupTrackProgressResolver.masteredCount(track: track, studentID: student2ID, lessons: lessons, lessonPresentations: presentations) == 2)
        #expect(GroupTrackProgressResolver.currentLesson(track: track, studentID: student2ID, lessons: lessons, lessonPresentations: presentations) == nil)
    }
}

#endif
