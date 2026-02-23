//
//  LifecycleServiceTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 1: Service Layer Tests
//  Target: 25 tests for LifecycleService
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("LifecycleService Tests")
struct LifecycleServiceTests {

    // MARK: - Core Functionality Tests

    @Test("Record presentation creates LessonAssignment")
    func recordPresentationCreatesLessonAssignment() async throws {
        let deps = AppDependencies.makeTest()
        let builder = TestEntityBuilder(context: deps.modelContext)

        let student = try builder.buildStudent(firstName: "Alice", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Algebra Basics")
        let studentLesson = try builder.buildStudentLesson(lesson: lesson, students: [student])

        let presentedAt = Date()
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson, presentedAt: presentedAt, modelContext: deps.modelContext
        )

        #expect(result.lessonAssignment.id != UUID())
        #expect(result.lessonAssignment.state == .presented)
        #expect(result.lessonAssignment.presentedAt == presentedAt)
        #expect(result.lessonAssignment.lessonID == lesson.id.uuidString)
        #expect(result.lessonAssignment.studentIDs.contains(student.id.uuidString))
    }
    
    @Test("Record presentation creates WorkModel items")
    func recordPresentationCreatesWorkItems() async throws {
        let deps = AppDependencies.makeTest()
        let builder = TestEntityBuilder(context: deps.modelContext)

        let student1 = try builder.buildStudent(firstName: "Bob", lastName: "Student")
        let student2 = try builder.buildStudent(firstName: "Carol", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Geometry")
        let studentLesson = try builder.buildStudentLesson(lesson: lesson, students: [student1, student2])

        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson, presentedAt: Date(), modelContext: deps.modelContext
        )

        TestPatterns.expectCount(result.work, equals: 2)
        #expect(result.work.allSatisfy { $0.status == .active })

        let workStudentIDs = Set(result.work.map { $0.studentID })
        #expect(workStudentIDs.contains(student1.id.uuidString))
        #expect(workStudentIDs.contains(student2.id.uuidString))
    }
    
    @Test("Record presentation is idempotent")
    func recordPresentationIsIdempotent() async throws {
        let deps = AppDependencies.makeTest()
        let builder = TestEntityBuilder(context: deps.modelContext)

        let student = try builder.buildStudent(firstName: "Dave", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Calculus")
        let studentLesson = try builder.buildStudentLesson(lesson: lesson, students: [student])

        let presentedAt = Date()
        let firstResult = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson, presentedAt: presentedAt, modelContext: deps.modelContext
        )

        let secondResult = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson, presentedAt: presentedAt, modelContext: deps.modelContext
        )

        #expect(firstResult.lessonAssignment.id == secondResult.lessonAssignment.id)
        #expect(firstResult.work.count == secondResult.work.count)

        let allWork = try deps.modelContext.fetch(FetchDescriptor<WorkModel>())
        let workForPresentation = allWork.filter { $0.presentationID == firstResult.lessonAssignment.id.uuidString }
        TestPatterns.expectCount(workForPresentation, equals: 1)
    }
    
    @Test("Record presentation links to migratedFromStudentLessonID")
    func recordPresentationLinksMigrationID() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A StudentLesson with a specific ID
        let student = try builder.buildStudent(firstName: "Eve", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Physics")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // When: Recording a presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: LessonAssignment has migration link
        #expect(result.lessonAssignment.migratedFromStudentLessonID == studentLesson.id.uuidString)
    }
    
    @Test("Record presentation snapshots lesson title and subheading")
    func recordPresentationSnapshotsLessonData() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A lesson with title and subheading
        let student = try builder.buildStudent(firstName: "Frank", lastName: "Student")
        let lesson = try createTestLesson(
            name: "Ancient Rome",
            subject: "History",
            group: "Ancient History",
            context: context
        )
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // When: Recording a presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Title and subheading are frozen
        #expect(result.lessonAssignment.lessonTitleSnapshot == "Ancient Rome")
        #expect(result.lessonAssignment.lessonSubheadingSnapshot == "Test Subheading")
    }
    
    // MARK: - WorkModel Creation Tests
    
    @Test("Work items have correct presentationID link")
    func workItemsHavePresentationIDLink() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A presentation
        let student = try builder.buildStudent(firstName: "Grace", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Chemistry")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // When: Recording a presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Work items linked to presentation
        let presentationID = result.lessonAssignment.id.uuidString
        #expect(result.work.allSatisfy { $0.presentationID == presentationID })
    }
    
    @Test("Work items have correct student and lesson IDs")
    func workItemsHaveCorrectForeignKeys() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: Students and lesson
        let student1 = try builder.buildStudent(firstName: "Henry", lastName: "Student")
        let student2 = try builder.buildStudent(firstName: "Irene", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Biology")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student1, student2],
            context: context
        )
        
        // When: Recording a presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Each work item has correct IDs
        for work in result.work {
            #expect(work.lessonID == lesson.id.uuidString)
            #expect([student1.id.uuidString, student2.id.uuidString].contains(work.studentID))
        }
    }
    
    @Test("Work items created with practice lesson kind")
    func workItemsHavePracticeLessonKind() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A presentation
        let student = try builder.buildStudent(firstName: "Jack", lastName: "Student")
        let lesson = try builder.buildLesson(name: "English")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // When: Recording a presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Work items have practice lesson kind
        #expect(result.work.allSatisfy { $0.kind == .practiceLesson })
    }
    
    // MARK: - Orphaned ID Cleanup Tests
    
    @Test("cleanOrphanedStudentIDs removes invalid student IDs")
    func cleanOrphanedStudentIDsRemovesInvalidIDs() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: StudentLesson with valid and invalid student IDs
        let validStudent = try builder.buildStudent(firstName: "Karen", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Art")
        let invalidStudentID = UUID()
        
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [validStudent],
            context: context
        )
        // Manually add invalid ID
        studentLesson.studentIDs = [validStudent.id.uuidString, invalidStudentID.uuidString]
        
        // When: Recording presentation (which cleans orphaned IDs)
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Only valid student ID remains
        #expect(studentLesson.studentIDs.count == 1)
        #expect(studentLesson.studentIDs.contains(validStudent.id.uuidString))
        #expect(!studentLesson.studentIDs.contains(invalidStudentID.uuidString))
        
        // And work items only for valid student
        #expect(result.work.count == 1)
        #expect(result.work[0].studentID == validStudent.id.uuidString)
    }
    
    @Test("cleanOrphanedStudentIDs handles empty student list")
    func cleanOrphanedStudentIDsHandlesEmptyList() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: All students deleted
        let lesson = try builder.buildLesson(name: "Music")
        let invalidStudentID1 = UUID()
        let invalidStudentID2 = UUID()
        
        let studentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: [invalidStudentID1, invalidStudentID2]
        )
        studentLesson.lesson = lesson
        context.insert(studentLesson)
        try context.save()
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Student IDs cleared, no work items created
        #expect(studentLesson.studentIDs.isEmpty)
        #expect(result.work.isEmpty)
    }
    
    // MARK: - LessonPresentation Upsert Tests
    
    @Test("Record presentation creates LessonPresentation records")
    func recordPresentationCreatesLessonPresentations() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A presentation
        let student = try builder.buildStudent(firstName: "Leo", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Latin")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // When: Recording a presentation
        let presentedAt = Date()
        _ = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // Then: LessonPresentation record exists
        let allPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        let studentPresentations = allPresentations.filter {
            $0.studentID == student.id.uuidString && $0.lessonID == lesson.id.uuidString
        }
        
        TestPatterns.expectCount(studentPresentations, equals: 1)
        let presentation = studentPresentations[0]
        #expect(presentation.state == .presented)
        #expect(presentation.presentedAt == presentedAt)
        #expect(presentation.lastObservedAt == presentedAt)
    }
    
    @Test("LessonPresentation upsert updates existing records")
    func lessonPresentationUpsertUpdatesExisting() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: An existing presentation
        let student = try builder.buildStudent(firstName: "Mia", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Drama")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        let firstPresentedAt = Date(timeIntervalSinceNow: -86400) // Yesterday
        _ = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: firstPresentedAt,
            modelContext: context
        )
        
        // When: Recording the same presentation again with new date
        let secondPresentedAt = Date()
        _ = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: secondPresentedAt,
            modelContext: context
        )
        
        // Then: Only one LessonPresentation exists with updated lastObservedAt
        let allPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        let studentPresentations = allPresentations.filter {
            $0.studentID == student.id.uuidString && $0.lessonID == lesson.id.uuidString
        }
        
        TestPatterns.expectCount(studentPresentations, equals: 1)
        let presentation = studentPresentations[0]
        #expect(presentation.lastObservedAt == secondPresentedAt)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Record presentation throws error for invalid lesson ID")
    func recordPresentationThrowsForInvalidLessonID() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: StudentLesson with invalid lesson ID
        let student = try builder.buildStudent(firstName: "Noah", lastName: "Student")
        let studentLesson = StudentLesson(
            id: UUID(),
            lessonID: UUID(),
            studentIDs: [student.id]
        )
        studentLesson.lessonID = "invalid-uuid-string"
        studentLesson.students = [student]
        context.insert(studentLesson)
        try context.save()
        
        // When/Then: Recording presentation throws error
        #expect(throws: LifecycleError.self) {
            try LifecycleService.recordPresentationAndExplodeWork(
                from: studentLesson,
                presentedAt: Date(),
                modelContext: context
            )
        }
    }
    
    @Test("Record presentation handles invalid student IDs gracefully")
    func recordPresentationHandlesInvalidStudentIDsGracefully() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: StudentLesson with mix of valid and invalid student IDs
        let validStudent = try builder.buildStudent(firstName: "Olivia", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Geography")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [validStudent],
            context: context
        )
        // Add invalid student ID
        studentLesson.studentIDs = [validStudent.id.uuidString, "invalid-uuid"]
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Only work for valid student created
        #expect(result.work.count == 1)
        #expect(result.work[0].studentID == validStudent.id.uuidString)
    }
    
    // MARK: - State Update Tests
    
    @Test("Existing draft LessonAssignment updated to presented state")
    func existingDraftLessonAssignmentUpdatedToPresented() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: An existing LessonAssignment in draft state
        let student = try builder.buildStudent(firstName: "Paul", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Economics")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student],
            context: context
        )
        
        // Create draft LessonAssignment manually
        let draftAssignment = LessonAssignment(
            id: UUID(),
            createdAt: Date(),
            state: .draft,
            presentedAt: nil,
            lessonID: lesson.id,
            studentIDs: [student.id],
            lesson: lesson,
            trackID: nil,
            trackStepID: nil
        )
        draftAssignment.migratedFromStudentLessonID = studentLesson.id.uuidString
        context.insert(draftAssignment)
        try context.save()
        
        // When: Recording presentation
        let presentedAt = Date()
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // Then: Same assignment updated to presented state
        #expect(result.lessonAssignment.id == draftAssignment.id)
        #expect(result.lessonAssignment.state == .presented)
        #expect(result.lessonAssignment.presentedAt == presentedAt)
    }
    
    // MARK: - Fetch Helper Tests
    
    @Test("fetchAllWorkModels returns all work for presentation")
    func fetchAllWorkModelsReturnsAllWork() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: Multiple students in one presentation
        let student1 = try builder.buildStudent(firstName: "Quinn", lastName: "Student")
        let student2 = try builder.buildStudent(firstName: "Rachel", lastName: "Student")
        let student3 = try builder.buildStudent(firstName: "Sam", lastName: "Student")
        let lesson = try builder.buildLesson(name: "Philosophy")
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student1, student2, student3],
            context: context
        )
        
        // When: Recording presentation
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: All three work items returned
        #expect(result.work.count == 3)
        
        let studentIDs = Set(result.work.map { $0.studentID })
        #expect(studentIDs.contains(student1.id.uuidString))
        #expect(studentIDs.contains(student2.id.uuidString))
        #expect(studentIDs.contains(student3.id.uuidString))
    }
    
    // MARK: - Integration Tests
    
    @Test("Complete flow: StudentLesson to LessonAssignment to WorkModels")
    func completeFlowFromStudentLessonToWork() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: A fully set up StudentLesson
        let student1 = try builder.buildStudent(firstName: "Tina", lastName: "Student")
        let student2 = try builder.buildStudent(firstName: "Uma", lastName: "Student")
        let lesson = try createTestLesson(
            name: "World War II",
            subject: "History",
            group: "Modern History",
            context: context
        )
        let studentLesson = try builder.buildStudentLesson(
            lesson: lesson,
            students: [student1, student2],
            context: context
        )
        
        // When: Full presentation flow
        let presentedAt = Date()
        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson,
            presentedAt: presentedAt,
            modelContext: context
        )
        
        // Then: Complete data structure created
        // 1. LessonAssignment exists and is presented
        #expect(result.lessonAssignment.state == .presented)
        #expect(result.lessonAssignment.presentedAt == presentedAt)
        #expect(result.lessonAssignment.lessonTitleSnapshot == "World War II")
        
        // 2. WorkModels created for both students
        #expect(result.work.count == 2)
        #expect(result.work.allSatisfy { $0.status == .active })
        #expect(result.work.allSatisfy { $0.kind == .practiceLesson })
        
        // 3. LessonPresentation records created
        let allPresentations = try context.fetch(FetchDescriptor<LessonPresentation>())
        let relevantPresentations = allPresentations.filter {
            $0.lessonID == lesson.id.uuidString &&
            [student1.id.uuidString, student2.id.uuidString].contains($0.studentID)
        }
        TestPatterns.expectCount(relevantPresentations, equals: 2)
        
        // 4. All records properly linked
        let presentationID = result.lessonAssignment.id.uuidString
        #expect(result.work.allSatisfy { $0.presentationID == presentationID })
        #expect(relevantPresentations.allSatisfy { $0.presentationID == presentationID })
    }
    
    @Test("Multiple presentations create separate data structures")
    func multiplePresentationsCreateSeparateStructures() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Given: Two different presentations
        let student = try builder.buildStudent(firstName: "Victor", lastName: "Student")
        let lesson1 = try createTestLesson(name: "Algebra I", subject: "Math", group: "Algebra", context: context)
        let lesson2 = try createTestLesson(name: "Algebra II", subject: "Math", group: "Algebra", context: context)
        
        let studentLesson1 = try builder.buildStudentLesson(lesson: lesson1, students: [student], context: context)
        let studentLesson2 = try builder.buildStudentLesson(lesson: lesson2, students: [student], context: context)
        
        // When: Recording both presentations
        let result1 = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson1,
            presentedAt: Date(),
            modelContext: context
        )
        
        let result2 = try LifecycleService.recordPresentationAndExplodeWork(
            from: studentLesson2,
            presentedAt: Date(),
            modelContext: context
        )
        
        // Then: Separate LessonAssignments and WorkModels
        #expect(result1.lessonAssignment.id != result2.lessonAssignment.id)
        #expect(result1.work[0].id != result2.work[0].id)
        #expect(result1.work[0].presentationID != result2.work[0].presentationID)
    }
}

#endif
