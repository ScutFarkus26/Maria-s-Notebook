//
//  EmptyDataTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 6: Edge Case Tests
//  Target: 8 tests for empty data scenarios
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Edge Cases: Empty Data Handling")
@MainActor
struct EmptyDataTests {
    
    // MARK: - Empty Database Tests
    
    @Test("Today view handles empty database gracefully")
    func todayViewHandlesEmptyDatabase() async throws {
        // Given: Empty database
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: Date())
        
        // Then: Returns empty results without crashing
        #expect(data.scheduledStudentLessons.isEmpty)
        #expect(data.presentedStudentLessons.isEmpty)
        #expect(data.activeWorkItems.isEmpty)
        #expect(data.completedWorkItems.isEmpty)
    }
    
    @Test("WorkRepository handles no students gracefully")
    func workRepositoryHandlesNoStudents() async throws {
        // Given: Empty database
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Create lesson but no students
        let lesson = Lesson(
            name: "Test Lesson",
            lessonType: "Standard",
            subject: "Test",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        context.insert(lesson)
        try context.save()
        
        let repository = WorkRepository(context: context)
        
        // When: Trying to create work with non-existent student
        let nonExistentStudentID = UUID()
        
        // Then: Should handle gracefully
        let work = try repository.createWork(
            studentID: nonExistentStudentID,
            lessonID: lesson.id,
            title: "Test Work",
            kind: .practiceLesson,
            presentationID: nil,
            scheduledDate: nil
        )
        
        // Work created but student doesn't exist
        #expect(work.studentID == nonExistentStudentID.uuidString)
    }
    
    @Test("GroupTrackService handles no lessons gracefully")
    func groupTrackServiceHandlesNoLessons() async throws {
        // Given: Empty database
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // When: Getting available tracks with no lessons
        let tracks = try GroupTrackService.getAllAvailableTracks(
            from: [],
            modelContext: context
        )
        
        // Then: Returns empty array
        #expect(tracks.isEmpty)
    }
    
    // MARK: - Empty Collection Tests
    
    @Test("LifecycleService handles StudentLesson with no students")
    func lifecycleServiceHandlesStudentLessonWithNoStudents() async throws {
        // Given: StudentLesson with empty student list
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let lesson = Lesson(
            name: "Test Lesson",
            lessonType: "Standard",
            subject: "Test",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        context.insert(lesson)
        try context.save()
        
        let studentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: []  // Empty student list
        )
        studentLesson.lesson = lesson
        studentLesson.students = []
        context.insert(studentLesson)
        try context.save()
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Creates LessonAssignment but no work items
        #expect(result.lessonAssignment.studentIDs.isEmpty)
        #expect(result.work.isEmpty)
    }
    
    @Test("Attendance grid handles no students")
    func attendanceGridHandlesNoStudents() async throws {
        // Given: Empty database
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // When: Fetching attendance records
        let records = try context.fetch(FetchDescriptor<AttendanceDayRecord>())
        
        // Then: Empty array
        #expect(records.isEmpty)
        
        // When: Trying to load AttendanceStore with no students
        let store = AttendanceStore(modelContext: context)
        let students = try context.fetch(FetchDescriptor<Student>())
        
        // Then: No students
        #expect(students.isEmpty)
    }
    
    // MARK: - Empty String/Nil Tests
    
    @Test("Models handle empty string properties gracefully")
    func modelsHandleEmptyStringProperties() async throws {
        // Given: Models with empty strings
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // When: Creating student with empty name
        let student = Student(name: "")
        context.insert(student)
        
        // When: Creating lesson with empty fields
        let lesson = Lesson(
            name: "",  // Empty name
            lessonType: "",
            subject: "",
            subheading: "",
            description: "",
            body: "",
            materials: "",
            group: ""
        )
        context.insert(lesson)
        
        try context.save()
        
        // Then: Models saved successfully
        let fetchedStudents = try context.fetch(FetchDescriptor<Student>())
        let fetchedLessons = try context.fetch(FetchDescriptor<Lesson>())
        
        #expect(fetchedStudents.count == 1)
        #expect(fetchedLessons.count == 1)
        #expect(fetchedStudents[0].name == "")
        #expect(fetchedLessons[0].name == "")
    }
    
    @Test("Work models handle nil optional fields")
    func workModelsHandleNilOptionalFields() async throws {
        // Given: Work with minimal fields
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student = Student(name: "Test")
        let lesson = Lesson(
            name: "Test",
            lessonType: "Standard",
            subject: "Test",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        context.insert(student)
        context.insert(lesson)
        try context.save()
        
        // When: Creating work with nil optionals
        let work = WorkModel(
            title: "",  // Empty title
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: .active
        )
        // All optional fields nil
        work.completedAt = nil
        work.dueAt = nil
        work.lastTouchedAt = nil
        work.presentationID = nil
        work.trackID = nil
        work.scheduledNote = nil
        
        context.insert(work)
        try context.save()
        
        // Then: Work saved successfully
        let fetchedWork = try context.fetch(FetchDescriptor<WorkModel>())
        #expect(fetchedWork.count == 1)
        #expect(fetchedWork[0].title == "")
        #expect(fetchedWork[0].completedAt == nil)
        #expect(fetchedWork[0].presentationID == nil)
    }
    
    // MARK: - Zero Count Tests
    
    @Test("Queries handle zero results gracefully")
    func queriesHandleZeroResultsGracefully() async throws {
        // Given: Database with some data
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student = Student(name: "Test Student")
        context.insert(student)
        try context.save()
        
        // When: Querying for non-existent data
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { $0.status == .complete }
        )
        let work = try context.fetch(workDescriptor)
        
        let lessonDescriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.subject == "NonExistent" }
        )
        let lessons = try context.fetch(lessonDescriptor)
        
        // Then: Empty results, no crashes
        #expect(work.isEmpty)
        #expect(lessons.isEmpty)
        
        // And: Can perform operations on empty results
        let workCount = work.count
        let lessonNames = lessons.map { $0.name }
        
        #expect(workCount == 0)
        #expect(lessonNames.isEmpty)
    }
}

#endif
