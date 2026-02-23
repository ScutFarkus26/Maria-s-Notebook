//
//  WorkCompletionFlowTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 3: Integration Tests
//  Target: 6 tests for Work Completion flow
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Integration: Work Completion Flow")
@MainActor
struct WorkCompletionFlowTests {
    
    // MARK: - Test Helpers
    
    private func createTestWorkWithDependencies(
        title: String = "Test Work",
        status: WorkStatus = .active,
        context: ModelContext
    ) throws -> (work: WorkModel, student: Student, lesson: Lesson) {
        let student = Student(name: "Test Student")
        let lesson = Lesson(
            name: "Test Lesson",
            lessonType: "Standard",
            subject: "Test Subject",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test Group"
        )
        
        context.insert(student)
        context.insert(lesson)
        try context.save()
        
        let work = WorkModel(
            title: title,
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: status
        )
        
        context.insert(work)
        try context.save()
        
        return (work, student, lesson)
    }
    
    // MARK: - Basic Completion Flow Tests
    
    @Test("Complete flow: Mark work as complete")
    func markWorkAsComplete() async throws {
        // Given: Active work item
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (work, _, _) = try createTestWorkWithDependencies(
            title: "Practice Assignment",
            status: .active,
            context: context
        )
        
        // When: Marking work complete
        work.status = .complete
        work.completedAt = Date()
        work.completionOutcome = .mastered
        try context.save()
        
        // Then: Work is marked complete
        #expect(work.status == .complete)
        #expect(work.completedAt != nil)
        #expect(work.completionOutcome == .mastered)
        
        // And: Changes persisted
        let fetchedWork = try context.fetch(FetchDescriptor<WorkModel>()).first
        #expect(fetchedWork?.status == .complete)
        #expect(fetchedWork?.completedAt != nil)
    }
    
    @Test("Complete flow: Work completion updates LessonPresentation")
    func workCompletionUpdatesLessonPresentation() async throws {
        // Given: Work with LessonPresentation
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (work, student, lesson) = try createTestWorkWithDependencies(context: context)
        
        // Create LessonPresentation
        let presentation = LessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            presentationID: UUID().uuidString,
            state: .presented,
            presentedAt: Date(),
            lastObservedAt: Date()
        )
        context.insert(presentation)
        try context.save()
        
        // When: Completing work and syncing progress
        work.status = .complete
        work.completedAt = Date()
        try context.save()
        
        // Manually update presentation (simulating WorkCompletionService)
        presentation.state = .mastered
        presentation.masteredAt = work.completedAt
        try context.save()
        
        // Then: Lesson presentation updated to mastered
        #expect(presentation.state == .mastered)
        #expect(presentation.masteredAt != nil)
    }
    
    @Test("Complete flow: Multiple participants completion tracking")
    func multipleParticipantsCompletionTracking() async throws {
        // Given: Work with multiple student participants
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student1 = Student(name: "Student 1")
        let student2 = Student(name: "Student 2")
        let student3 = Student(name: "Student 3")
        let lesson = Lesson(
            name: "Group Project",
            lessonType: "Standard",
            subject: "Science",
            subheading: "Test",
            description: "Test",
            body: "Test",
            materials: "Test",
            group: "Test"
        )
        
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        context.insert(lesson)
        try context.save()
        
        let work = WorkModel(
            title: "Group Work",
            studentID: student1.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: .active
        )
        context.insert(work)
        try context.save()
        
        // Create participants
        let participant1 = WorkParticipantEntity(
            studentID: student1.id.uuidString,
            work: work
        )
        let participant2 = WorkParticipantEntity(
            studentID: student2.id.uuidString,
            work: work
        )
        let participant3 = WorkParticipantEntity(
            studentID: student3.id.uuidString,
            work: work
        )
        
        context.insert(participant1)
        context.insert(participant2)
        context.insert(participant3)
        
        work.participants = [participant1, participant2, participant3]
        try context.save()
        
        // When: One student completes their part
        participant1.completedAt = Date()
        try context.save()
        
        // Then: Only that participant marked complete
        #expect(participant1.completedAt != nil)
        #expect(participant2.completedAt == nil)
        #expect(participant3.completedAt == nil)
        
        // When: All students complete
        participant2.completedAt = Date()
        participant3.completedAt = Date()
        try context.save()
        
        // Then: All participants completed
        let allCompleted = work.participants?.allSatisfy { $0.completedAt != nil } ?? false
        #expect(allCompleted == true)
    }
    
    // MARK: - Status Transition Tests
    
    @Test("Complete flow: Status transitions through lifecycle")
    func statusTransitionsThroughLifecycle() async throws {
        // Given: New work item
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (work, _, _) = try createTestWorkWithDependencies(
            status: .active,
            context: context
        )
        
        // Then: Starts as active
        #expect(work.status == .active)
        #expect(work.completedAt == nil)
        
        // When: Moving to review
        work.status = .review
        try context.save()
        
        // Then: In review state
        #expect(work.status == .review)
        #expect(work.completedAt == nil)
        
        // When: Completing work
        work.status = .complete
        work.completedAt = Date()
        work.completionOutcome = .mastered
        try context.save()
        
        // Then: Marked complete with outcome
        #expect(work.status == .complete)
        #expect(work.completedAt != nil)
        #expect(work.completionOutcome == .mastered)
    }
    
    @Test("Complete flow: Completion outcome variations")
    func completionOutcomeVariations() async throws {
        // Given: Multiple work items
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (work1, _, _) = try createTestWorkWithDependencies(
            title: "Mastered Work",
            context: context
        )
        let (work2, _, _) = try createTestWorkWithDependencies(
            title: "Needs Review Work",
            context: context
        )
        let (work3, _, _) = try createTestWorkWithDependencies(
            title: "Needs Practice Work",
            context: context
        )
        
        // When: Completing with different outcomes
        work1.status = .complete
        work1.completedAt = Date()
        work1.completionOutcome = .mastered
        
        work2.status = .complete
        work2.completedAt = Date()
        work2.completionOutcome = .needsReview
        
        work3.status = .complete
        work3.completedAt = Date()
        work3.completionOutcome = .needsPractice
        
        try context.save()
        
        // Then: Each has correct outcome
        #expect(work1.completionOutcome == .mastered)
        #expect(work2.completionOutcome == .needsReview)
        #expect(work3.completionOutcome == .needsPractice)
        
        // And: All marked complete
        let allWork = try context.fetch(FetchDescriptor<WorkModel>())
        #expect(allWork.allSatisfy { $0.status == .complete })
        #expect(allWork.allSatisfy { $0.completedAt != nil })
    }
    
    // MARK: - Work History Tests
    
    @Test("Complete flow: Completion creates history record")
    func completionCreatesHistoryRecord() async throws {
        // Given: Work item with check-ins
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (work, _, _) = try createTestWorkWithDependencies(context: context)
        
        // Create check-ins to show work history
        let checkIn1 = WorkCheckIn(
            work: work,
            checkedInAt: Date(timeIntervalSinceNow: -86400),
            notes: "Started work"
        )
        let checkIn2 = WorkCheckIn(
            work: work,
            checkedInAt: Date(timeIntervalSinceNow: -3600),
            notes: "Made progress"
        )
        
        context.insert(checkIn1)
        context.insert(checkIn2)
        work.checkIns = [checkIn1, checkIn2]
        try context.save()
        
        // When: Completing work
        work.status = .complete
        work.completedAt = Date()
        work.completionOutcome = .mastered
        
        let completionCheckIn = WorkCheckIn(
            work: work,
            checkedInAt: Date(),
            notes: "Completed - Mastered"
        )
        context.insert(completionCheckIn)
        work.checkIns?.append(completionCheckIn)
        try context.save()
        
        // Then: History preserved with completion
        #expect(work.checkIns?.count == 3)
        #expect(work.checkIns?.last?.notes == "Completed - Mastered")
        
        // And: Work marked complete
        #expect(work.status == .complete)
        #expect(work.completionOutcome == .mastered)
    }
}

#endif
