//
//  ConcurrentAccessTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 6: Edge Case Tests
//  Target: 7 tests for concurrent access scenarios
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Edge Cases: Concurrent Access")
@MainActor
struct ConcurrentAccessTests {
    
    // MARK: - Concurrent Read Tests
    
    @Test("Multiple concurrent reads don't cause issues")
    func multipleConcurrentReadsDontCauseIssues() async throws {
        // Given: Database with test data
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // Seed data
        for i in 1...100 {
            let student = Student(name: "Student \(i)")
            context.insert(student)
        }
        try context.save()
        
        // When: Multiple concurrent reads
        await withTaskGroup(of: Int.self) { group in
            for iteration in 1...10 {
                group.addTask { @MainActor in
                    let descriptor = FetchDescriptor<Student>()
                    let students = try? context.fetch(descriptor)
                    return students?.count ?? 0
                }
            }
            
            // Then: All reads complete successfully
            var totalReads = 0
            for await count in group {
                totalReads += 1
                #expect(count == 100, "Read returned \(count) students, expected 100")
            }
            
            #expect(totalReads == 10, "Expected 10 concurrent reads")
        }
    }
    
    @Test("Concurrent queries return consistent results")
    func concurrentQueriesReturnConsistentResults() async throws {
        // Given: Database with specific data
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
        
        for i in 1...50 {
            let work = WorkModel(
                title: "Work \(i)",
                studentID: student.id.uuidString,
                lessonID: lesson.id.uuidString,
                kind: .practiceLesson,
                status: i % 2 == 0 ? .complete : .active
            )
            context.insert(work)
        }
        try context.save()
        
        // When: Multiple concurrent queries for active work
        await withTaskGroup(of: Int.self) { group in
            for _ in 1...5 {
                group.addTask { @MainActor in
                    let descriptor = FetchDescriptor<WorkModel>(
                        predicate: #Predicate { $0.status == .active }
                    )
                    let activeWork = try? context.fetch(descriptor)
                    return activeWork?.count ?? 0
                }
            }
            
            // Then: All queries return same count
            var results: [Int] = []
            for await count in group {
                results.append(count)
            }
            
            #expect(results.count == 5)
            let firstCount = results[0]
            #expect(results.allSatisfy { $0 == firstCount }, "Inconsistent results: \(results)")
        }
    }
    
    // MARK: - Mixed Read/Write Tests
    
    @Test("Reads during writes remain consistent")
    func readsDuringWritesRemainConsistent() async throws {
        // Given: Initial database state
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        for i in 1...20 {
            let student = Student(name: "Student \(i)")
            context.insert(student)
        }
        try context.save()
        
        let initialCount = try context.fetch(FetchDescriptor<Student>()).count
        
        // When: Reading while performing writes
        await withTaskGroup(of: Int.self) { group in
            // Add writer task
            group.addTask { @MainActor in
                for i in 21...30 {
                    let student = Student(name: "Student \(i)")
                    context.insert(student)
                }
                try? context.save()
                return 0  // Writer task marker
            }
            
            // Add reader tasks
            for _ in 1...5 {
                group.addTask { @MainActor in
                    let descriptor = FetchDescriptor<Student>()
                    let students = try? context.fetch(descriptor)
                    return students?.count ?? 0
                }
            }
            
            // Collect results
            var readerResults: [Int] = []
            for await result in group {
                if result != 0 {
                    readerResults.append(result)
                }
            }
            
            // Then: Readers get valid counts (either before or after write)
            #expect(readerResults.count == 5)
            #expect(readerResults.allSatisfy { $0 == initialCount || $0 == initialCount + 10 })
        }
    }
    
    // MARK: - SwiftData Thread Safety Tests
    
    @Test("ModelContext operations are thread-safe")
    func modelContextOperationsAreThreadSafe() async throws {
        // Given: Model context
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        // When: Concurrent inserts (on main actor)
        await withTaskGroup(of: Void.self) { group in
            for i in 1...20 {
                group.addTask { @MainActor in
                    let student = Student(name: "Concurrent Student \(i)")
                    context.insert(student)
                }
            }
            
            await group.waitForAll()
        }
        
        try context.save()
        
        // Then: All students saved
        let students = try context.fetch(FetchDescriptor<Student>())
        #expect(students.count == 20)
    }
    
    @Test("Fetch operations don't interfere with each other")
    func fetchOperationsDontInterfereWithEachOther() async throws {
        // Given: Database with varied data
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        for i in 1...30 {
            let student = Student(name: "Student \(i)")
            context.insert(student)
            
            let lesson = Lesson(
                name: "Lesson \(i)",
                lessonType: "Standard",
                subject: "Subject \(i % 5)",
                subheading: "Test",
                description: "Test",
                body: "Test",
                materials: "Test",
                group: "Group \(i % 3)"
            )
            context.insert(lesson)
        }
        try context.save()
        
        // When: Multiple different fetches concurrently
        await withTaskGroup(of: (String, Int).self) { group in
            group.addTask { @MainActor in
                let students = try? context.fetch(FetchDescriptor<Student>())
                return ("students", students?.count ?? 0)
            }
            
            group.addTask { @MainActor in
                let lessons = try? context.fetch(FetchDescriptor<Lesson>())
                return ("lessons", lessons?.count ?? 0)
            }
            
            group.addTask { @MainActor in
                let descriptor = FetchDescriptor<Student>(
                    sortBy: [SortDescriptor(\.name)]
                )
                let sorted = try? context.fetch(descriptor)
                return ("sorted_students", sorted?.count ?? 0)
            }
            
            // Collect results
            var results: [String: Int] = [:]
            for await (key, count) in group {
                results[key] = count
            }
            
            // Then: All fetches return correct counts
            #expect(results["students"] == 30)
            #expect(results["lessons"] == 30)
            #expect(results["sorted_students"] == 30)
        }
    }
    
    // MARK: - Race Condition Tests
    
    @Test("Status updates don't create race conditions")
    func statusUpdatesDontCreateRaceConditions() async throws {
        // Given: Shared work item
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
        
        let work = WorkModel(
            title: "Shared Work",
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            kind: .practiceLesson,
            status: .active
        )
        context.insert(work)
        try context.save()
        
        let workID = work.id
        
        // When: Multiple tasks try to update status
        await withTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask { @MainActor in
                    let descriptor = FetchDescriptor<WorkModel>(
                        predicate: #Predicate { $0.id == workID }
                    )
                    if let work = try? context.fetch(descriptor).first {
                        // Simulate different status updates
                        if i % 2 == 0 {
                            work.status = .review
                        } else {
                            work.status = .complete
                        }
                    }
                }
            }
            
            await group.waitForAll()
        }
        
        try context.save()
        
        // Then: Work has one of the valid final states
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { $0.id == workID }
        )
        let finalWork = try context.fetch(descriptor).first
        
        #expect(finalWork != nil)
        #expect([WorkStatus.review, WorkStatus.complete].contains(finalWork!.status))
    }
    
    // MARK: - Data Consistency Tests
    
    @Test("Concurrent data access maintains referential integrity")
    func concurrentDataAccessMaintainsReferentialIntegrity() async throws {
        // Given: Related entities
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student = Student(name: "Test Student")
        context.insert(student)
        try context.save()
        
        let studentID = student.id
        
        // When: Creating multiple work items for same student concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask { @MainActor in
                    let lesson = Lesson(
                        name: "Lesson \(i)",
                        lessonType: "Standard",
                        subject: "Test",
                        subheading: "Test",
                        description: "Test",
                        body: "Test",
                        materials: "Test",
                        group: "Test"
                    )
                    context.insert(lesson)
                    try? context.save()
                    
                    let work = WorkModel(
                        title: "Work \(i)",
                        studentID: studentID.uuidString,
                        lessonID: lesson.id.uuidString,
                        kind: .practiceLesson,
                        status: .active
                    )
                    context.insert(work)
                }
            }
            
            await group.waitForAll()
        }
        
        try context.save()
        
        // Then: All work items reference valid student
        let workDescriptor = FetchDescriptor<WorkModel>()
        let allWork = try context.fetch(workDescriptor)
        
        #expect(allWork.count == 10)
        #expect(allWork.allSatisfy { $0.studentID == studentID.uuidString })
        
        // And: Student still exists
        let studentDescriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == studentID }
        )
        let students = try context.fetch(studentDescriptor)
        #expect(students.count == 1)
    }
}

#endif
