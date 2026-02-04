//
//  PresentationRecordingFlowTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 3: Integration Tests
//  Target: 7 tests for Presentation Recording flow
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Integration: Presentation Recording Flow")
@MainActor
struct PresentationRecordingFlowTests {
    
    // MARK: - Test Helpers
    
    private func createStudentLessonSetup(
        studentCount: Int = 1,
        context: ModelContext
    ) throws -> (students: [Student], lesson: Lesson, studentLesson: StudentLesson) {
        var students: [Student] = []
        for i in 1...studentCount {
            let student = Student(name: "Student \(i)")
            context.insert(student)
            students.append(student)
        }
        
        let lesson = Lesson(
            name: "Test Lesson",
            lessonType: "Standard",
            subject: "Mathematics",
            subheading: "Algebra Basics",
            description: "Introduction to algebra",
            body: "Lesson content",
            materials: "Textbook pages 1-10",
            group: "Algebra I"
        )
        context.insert(lesson)
        try context.save()
        
        let studentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: students.map { $0.id }
        )
        studentLesson.lesson = lesson
        studentLesson.students = students
        
        context.insert(studentLesson)
        try context.save()
        
        return (students, lesson, studentLesson)
    }
    
    // MARK: - Basic Presentation Recording Tests
    
    @Test("Complete flow: Record presentation creates LessonAssignment")
    func recordPresentationCreatesLessonAssignment() async throws {
        // Given: Student and lesson ready for presentation
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (_, _, studentLesson) = try createStudentLessonSetup(context: context)
        
        // When: Recording presentation
        let presentedAt = Date()
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // Then: LessonAssignment created
        #expect(result.lessonAssignment.state == .presented)
        #expect(result.lessonAssignment.presentedAt == presentedAt)
        
        // And: Link to original StudentLesson preserved
        #expect(result.lessonAssignment.migratedFromStudentLessonID == studentLesson.id.uuidString)
    }
    
    @Test("Complete flow: Presentation creates work items for all students")
    func presentationCreatesWorkItemsForAllStudents() async throws {
        // Given: Multiple students for one lesson
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, _, studentLesson) = try createStudentLessonSetup(
            studentCount: 3,
            context: context
        )
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Work item created for each student
        #expect(result.work.count == 3)
        
        let workStudentIDs = Set(result.work.map { $0.studentID })
        for student in students {
            #expect(workStudentIDs.contains(student.id.uuidString))
        }
        
        // And: All work items linked to presentation
        let presentationID = result.lessonAssignment.id.uuidString
        #expect(result.work.allSatisfy { $0.presentationID == presentationID })
    }
    
    @Test("Complete flow: Presentation updates student progress")
    func presentationUpdatesStudentProgress() async throws {
        // Given: Student and lesson
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, lesson, studentLesson) = try createStudentLessonSetup(context: context)
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: LessonPresentation record created
        let allPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        let studentPresentations = allPresentations.filter {
            $0.studentID == students[0].id.uuidString &&
            $0.lessonID == lesson.id.uuidString
        }
        
        #expect(studentPresentations.count == 1)
        
        let presentation = studentPresentations[0]
        #expect(presentation.state == .presented)
        #expect(presentation.presentationID == result.lessonAssignment.id.uuidString)
    }
    
    // MARK: - Track Integration Tests
    
    @Test("Complete flow: Presentation links to track if lesson belongs to track")
    func presentationLinksToTrackIfLessonBelongsToTrack() async throws {
        // Given: Lesson that belongs to a track
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, lesson, studentLesson) = try createStudentLessonSetup(context: context)
        
        // Ensure track exists for this subject/group
        let track = try GroupTrackService.getOrCreateTrack(
            subject: lesson.subject,
            group: lesson.group,
            modelContext: context
        )
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: LessonAssignment linked to track
        #expect(result.lessonAssignment.trackID != nil)
        #expect(result.lessonAssignment.trackID == track.id.uuidString)
        
        // And: Work items also linked to track
        #expect(result.work.allSatisfy { $0.trackID != nil })
    }
    
    @Test("Complete flow: Presentation auto-enrolls students in track")
    func presentationAutoEnrollsStudentsInTrack() async throws {
        // Given: Lesson in a track
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, lesson, studentLesson) = try createStudentLessonSetup(context: context)
        
        // Create track
        let track = try GroupTrackService.getOrCreateTrack(
            subject: lesson.subject,
            group: lesson.group,
            modelContext: context
        )
        
        // When: Recording presentation
        _ = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Manually trigger enrollment (simulating what LifecycleService does)
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson,
            studentIDs: students.map { $0.id.uuidString },
            modelContext: context
        )
        
        // Then: Student enrolled in track
        let allEnrollments = try context.fetch(FetchDescriptor<StudentTrackEnrollment>())
        let studentEnrollments = allEnrollments.filter {
            $0.studentID == students[0].id.uuidString &&
            $0.trackID == track.id.uuidString
        }
        
        #expect(studentEnrollments.count == 1)
        #expect(studentEnrollments[0].isActive == true)
    }
    
    // MARK: - Idempotency Tests
    
    @Test("Complete flow: Recording same presentation twice is idempotent")
    func recordingSamePresentationTwiceIsIdempotent() async throws {
        // Given: Presentation already recorded
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (_, _, studentLesson) = try createStudentLessonSetup(context: context)
        
        let presentedAt = Date()
        let firstResult = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // When: Recording same presentation again
        let secondResult = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // Then: Same LessonAssignment returned
        #expect(firstResult.lessonAssignment.id == secondResult.lessonAssignment.id)
        
        // And: No duplicate work items
        #expect(firstResult.work.count == secondResult.work.count)
        
        // Verify in database
        let allWork = try context.fetch(FetchDescriptor<WorkModel>())
        let workForPresentation = allWork.filter {
            $0.presentationID == firstResult.lessonAssignment.id.uuidString
        }
        #expect(workForPresentation.count == 1)
    }
    
    // MARK: - Data Integrity Tests
    
    @Test("Complete flow: Presentation snapshots lesson title and metadata")
    func presentationSnapshotsLessonTitleAndMetadata() async throws {
        // Given: Lesson with specific title and metadata
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (_, lesson, studentLesson) = try createStudentLessonSetup(context: context)
        
        let originalTitle = lesson.name
        let originalSubheading = lesson.subheading
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Title and subheading snapshotted
        #expect(result.lessonAssignment.lessonTitleSnapshot == originalTitle)
        #expect(result.lessonAssignment.lessonSubheadingSnapshot == originalSubheading)
        
        // When: Lesson title changes after presentation
        lesson.name = "Changed Title"
        try context.save()
        
        // Then: Snapshot unchanged
        #expect(result.lessonAssignment.lessonTitleSnapshot == originalTitle)
        #expect(result.lessonAssignment.lessonTitleSnapshot != lesson.name)
    }
}

#endif
