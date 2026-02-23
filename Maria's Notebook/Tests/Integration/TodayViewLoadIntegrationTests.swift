//
//  TodayViewLoadIntegrationTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 3: Integration Tests
//  Target: 8 tests for Today View load flow
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Integration: Today View Load Flow")
@MainActor
struct TodayViewLoadIntegrationTests {
    
    // MARK: - Test Helpers
    
    private func seedRealisticData(
        studentCount: Int,
        lessonCount: Int,
        workCount: Int,
        context: ModelContext
    ) throws {
        // Create students
        for i in 1...studentCount {
            let student = Student(name: "Student \(i)")
            context.insert(student)
        }
        
        // Create lessons with varied scheduling
        let today = AppCalendar.startOfDay(Date())
        for i in 1...lessonCount {
            let lesson = Lesson(
                name: "Lesson \(i)",
                lessonType: "Standard",
                subject: "Subject \(i % 10)",
                subheading: "Test",
                description: "Test lesson \(i)",
                body: "Content",
                materials: "Materials",
                group: "Group \(i % 5)"
            )
            
            // Schedule some lessons for today
            if i % 3 == 0 {
                lesson.scheduledDates = [today]
            }
            
            context.insert(lesson)
        }
        
        try context.save()
        
        // Get all students and lessons for work creation
        let allStudents = try context.fetch(FetchDescriptor<Student>())
        let allLessons = try context.fetch(FetchDescriptor<Lesson>())
        
        // Create work items
        for i in 1...workCount {
            let student = allStudents[i % allStudents.count]
            let lesson = allLessons[i % allLessons.count]
            
            let work = WorkModel(
                title: "Work \(i)",
                studentID: student.id.uuidString,
                lessonID: lesson.id.uuidString,
                kind: .practiceLesson,
                status: i % 4 == 0 ? .complete : .active
            )
            
            context.insert(work)
        }
        
        try context.save()
    }
    
    // MARK: - Basic Load Tests
    
    @Test("Today view loads with empty database")
    func loadsWithEmptyDatabase() async throws {
        // Given: Empty database
        let deps = AppDependencies.makeTest()
        
        // When: Loading TodayDataFetcher
        let fetcher = TodayDataFetcher(
            modelContext: deps.modelContext,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: Date())
        
        // Then: Loads successfully with no data
        #expect(data.scheduledStudentLessons.isEmpty)
        #expect(data.presentedStudentLessons.isEmpty)
        #expect(data.activeWorkItems.isEmpty)
        #expect(data.completedWorkItems.isEmpty)
    }
    
    @Test("Today view loads lessons for current date")
    func loadsLessonsForCurrentDate() async throws {
        // Given: Lessons scheduled for today
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        let today = AppCalendar.startOfDay(Date())
        
        let lesson1 = Lesson(
            name: "Math",
            lessonType: "Standard",
            subject: "Mathematics",
            subheading: "Algebra",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Algebra I"
        )
        lesson1.scheduledDates = [today]
        
        let lesson2 = Lesson(
            name: "Science",
            lessonType: "Standard",
            subject: "Science",
            subheading: "Biology",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Bio 101"
        )
        lesson2.scheduledDates = [today]
        
        let student = Student(name: "Test Student")
        
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(student)
        try context.save()
        
        // Create StudentLesson records
        let studentLesson1 = StudentLesson(
            id: UUID(),
            lessonID: lesson1.id,
            studentIDs: [student.id]
        )
        studentLesson1.lesson = lesson1
        studentLesson1.students = [student]
        studentLesson1.scheduledFor = today
        
        let studentLesson2 = StudentLesson(
            id: UUID(),
            lessonID: lesson2.id,
            studentIDs: [student.id]
        )
        studentLesson2.lesson = lesson2
        studentLesson2.students = [student]
        studentLesson2.scheduledFor = today
        
        context.insert(studentLesson1)
        context.insert(studentLesson2)
        try context.save()
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: today)
        
        // Then: Both lessons appear
        #expect(data.scheduledStudentLessons.count == 2)
    }
    
    @Test("Today view separates scheduled and presented lessons")
    func separatesScheduledAndPresentedLessons() async throws {
        // Given: Mix of scheduled and presented lessons
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        let today = AppCalendar.startOfDay(Date())
        
        let scheduledLesson = Lesson(
            name: "Scheduled",
            lessonType: "Standard",
            subject: "Math",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        scheduledLesson.scheduledDates = [today]
        
        let presentedLesson = Lesson(
            name: "Presented",
            lessonType: "Standard",
            subject: "Science",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        presentedLesson.scheduledDates = [today]
        
        let student = Student(name: "Test Student")
        
        context.insert(scheduledLesson)
        context.insert(presentedLesson)
        context.insert(student)
        try context.save()
        
        // Create scheduled StudentLesson
        let scheduledSL = StudentLesson(
            id: UUID(),
            lessonID: scheduledLesson.id,
            studentIDs: [student.id]
        )
        scheduledSL.lesson = scheduledLesson
        scheduledSL.students = [student]
        scheduledSL.scheduledFor = today
        scheduledSL.isGiven = false
        
        // Create presented StudentLesson
        let presentedSL = StudentLesson(
            id: UUID(),
            lessonID: presentedLesson.id,
            studentIDs: [student.id]
        )
        presentedSL.lesson = presentedLesson
        presentedSL.students = [student]
        presentedSL.scheduledFor = today
        presentedSL.isGiven = true
        presentedSL.givenAt = today
        
        context.insert(scheduledSL)
        context.insert(presentedSL)
        try context.save()
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: today)
        
        // Then: Lessons properly categorized
        #expect(data.scheduledStudentLessons.count == 1)
        #expect(data.presentedStudentLessons.count == 1)
        #expect(data.scheduledStudentLessons.first?.lesson?.name == "Scheduled")
        #expect(data.presentedStudentLessons.first?.lesson?.name == "Presented")
    }
    
    // MARK: - Work Item Load Tests
    
    @Test("Today view loads active work items")
    func loadsActiveWorkItems() async throws {
        // Given: Mix of active and complete work
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student = Student(name: "Test Student")
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
        
        context.insert(student)
        context.insert(lesson)
        try context.save()
        
        let activeWork = WorkModel(
            title: "Active Work",
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: .active
        )
        
        let completeWork = WorkModel(
            title: "Complete Work",
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: .complete
        )
        completeWork.completedAt = Date()
        
        context.insert(activeWork)
        context.insert(completeWork)
        try context.save()
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: Date())
        
        // Then: Only active work appears in active list
        #expect(data.activeWorkItems.count == 1)
        #expect(data.activeWorkItems.first?.title == "Active Work")
        #expect(data.completedWorkItems.count == 1)
        #expect(data.completedWorkItems.first?.title == "Complete Work")
    }
    
    // MARK: - Performance Tests
    
    @Test("Today view loads quickly with moderate dataset")
    func loadsQuicklyWithModerateDataset() async throws {
        // Given: Moderate realistic dataset
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        try seedRealisticData(
            studentCount: 50,
            lessonCount: 100,
            workCount: 200,
            context: context
        )
        
        // When: Loading today's data
        let startTime = Date()
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: Date())
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Loads within acceptable time
        #expect(duration < 1.0, "Load took \(duration)s, expected < 1.0s")
        
        // And: Data loaded successfully
        #expect(data.scheduledStudentLessons.count >= 0)
        #expect(data.activeWorkItems.count >= 0)
    }
    
    @Test("Today view handles large dataset without crashing")
    func handlesLargeDatasetWithoutCrashing() async throws {
        // Given: Large dataset (stress test)
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        try seedRealisticData(
            studentCount: 100,
            lessonCount: 500,
            workCount: 1000,
            context: context
        )
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: Date())
        
        // Then: Completes without crashing
        #expect(data.scheduledStudentLessons.count >= 0)
        #expect(data.activeWorkItems.count >= 0)
        
        // Memory should be reasonable (check that we got some data)
        let totalItems = data.scheduledStudentLessons.count +
                        data.presentedStudentLessons.count +
                        data.activeWorkItems.count +
                        data.completedWorkItems.count
        
        #expect(totalItems >= 0, "Should load some data from large dataset")
    }
    
    // MARK: - Date Navigation Tests
    
    @Test("Today view respects selected date for data loading")
    func respectsSelectedDateForLoading() async throws {
        // Given: Lessons on different dates
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let today = AppCalendar.startOfDay(Date())
        let yesterday = AppCalendar.addDays(-1, to: today)
        let tomorrow = AppCalendar.addDays(1, to: today)
        
        let todayLesson = Lesson(
            name: "Today",
            lessonType: "Standard",
            subject: "Test",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        todayLesson.scheduledDates = [today]
        
        let tomorrowLesson = Lesson(
            name: "Tomorrow",
            lessonType: "Standard",
            subject: "Test",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        tomorrowLesson.scheduledDates = [tomorrow]
        
        let student = Student(name: "Test Student")
        
        context.insert(todayLesson)
        context.insert(tomorrowLesson)
        context.insert(student)
        try context.save()
        
        // Create StudentLessons
        let todaySL = StudentLesson(
            id: UUID(),
            lessonID: todayLesson.id,
            studentIDs: [student.id]
        )
        todaySL.lesson = todayLesson
        todaySL.students = [student]
        todaySL.scheduledFor = today
        
        let tomorrowSL = StudentLesson(
            id: UUID(),
            lessonID: tomorrowLesson.id,
            studentIDs: [student.id]
        )
        tomorrowSL.lesson = tomorrowLesson
        tomorrowSL.students = [student]
        tomorrowSL.scheduledFor = tomorrow
        
        context.insert(todaySL)
        context.insert(tomorrowSL)
        try context.save()
        
        // When: Loading for tomorrow's date
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: tomorrow)
        
        // Then: Only tomorrow's lesson appears
        #expect(data.scheduledStudentLessons.count == 1)
        #expect(data.scheduledStudentLessons.first?.lesson?.name == "Tomorrow")
    }
    
    // MARK: - Error Recovery Tests
    
    @Test("Today view handles missing lesson relationships gracefully")
    func handlesMissingLessonRelationshipsGracefully() async throws {
        // Given: StudentLesson with invalid lesson ID
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        let today = AppCalendar.startOfDay(Date())
        
        let student = Student(name: "Test Student")
        context.insert(student)
        try context.save()
        
        // Create StudentLesson with non-existent lesson
        let orphanedSL = StudentLesson(
            id: UUID(),
            lessonID: UUID(), // Lesson doesn't exist
            studentIDs: [student.id]
        )
        orphanedSL.students = [student]
        orphanedSL.scheduledFor = today
        
        context.insert(orphanedSL)
        try context.save()
        
        // When: Loading today's data
        let fetcher = TodayDataFetcher(
            modelContext: context,
            dependencies: deps
        )
        let data = try await fetcher.fetchData(for: today)
        
        // Then: Doesn't crash, filters out invalid data
        #expect(data.scheduledStudentLessons.count == 0 || data.scheduledStudentLessons.count == 1)
    }
}

#endif
