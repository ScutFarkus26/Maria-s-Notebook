import Foundation
import SwiftData

// MARK: - WorkModel Extensions

extension WorkModel {
    /// Fetches the presentation that spawned this work item
    func fetchPresentation(from context: ModelContext) -> Presentation? {
        guard let presentationID = presentationID,
              let uuid = UUID(uuidString: presentationID) else { return nil }
        
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    /// Fetches the lesson associated with this work item
    func fetchLesson(from context: ModelContext) -> Lesson? {
        guard !lessonID.isEmpty,
              let uuid = UUID(uuidString: lessonID) else { return nil }
        
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    /// Fetches the student assigned to this work item
    func fetchStudent(from context: ModelContext) -> Student? {
        guard !studentID.isEmpty,
              let uuid = UUID(uuidString: studentID) else { return nil }
        
        let descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    /// Fetches all practice sessions that include this work item
    func fetchPracticeSessions(from context: ModelContext) -> [PracticeSession] {
        let workIDString = id.uuidString
        
        // Fetch all practice sessions and filter in memory
        // This is necessary because SwiftData predicates don't support contains() on string arrays
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let allSessions = (try? context.fetch(descriptor)) ?? []
        return allSessions.filter { session in
            session.workItemIDs.contains(workIDString)
        }
    }
}

// MARK: - Presentation (LessonAssignment) Extensions

extension LessonAssignment {
    /// Fetches all work items spawned from this presentation
    func fetchRelatedWork(from context: ModelContext) -> [WorkModel] {
        let presentationIDString = id.uuidString
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { $0.presentationID == presentationIDString },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetches all students assigned to this presentation
    func fetchStudents(from context: ModelContext) -> [Student] {
        let studentUUIDStrings = studentIDs
        guard !studentUUIDStrings.isEmpty else { return [] }
        
        // Convert string IDs to UUIDs
        let uuids = studentUUIDStrings.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }
        
        // Fetch all students and filter in-memory
        // This is necessary because SwiftData predicates don't support id.uuidString keypaths
        let descriptor = FetchDescriptor<Student>(
            sortBy: [SortDescriptor(\.firstName)]
        )
        
        let allStudents = (try? context.fetch(descriptor)) ?? []
        return allStudents.filter { student in
            studentUUIDStrings.contains(student.id.uuidString)
        }
    }
    
    /// Fetches practice sessions related to work from this presentation
    func fetchRelatedPracticeSessions(from context: ModelContext) -> [PracticeSession] {
        let workItems = fetchRelatedWork(from: context)
        let workIDs = Set(workItems.map { $0.id.uuidString })
        guard !workIDs.isEmpty else { return [] }
        
        // Fetch all practice sessions and filter in memory
        // This is necessary because SwiftData predicates don't support complex array operations
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let allSessions = (try? context.fetch(descriptor)) ?? []
        return allSessions.filter { session in
            session.workItemIDs.contains(where: { workIDs.contains($0) })
        }
    }
    
    /// Returns work completion statistics for this presentation
    func workCompletionStats(from context: ModelContext) -> (completed: Int, total: Int) {
        let work = fetchRelatedWork(from: context)
        let completed = work.filter { $0.status == .complete }.count
        return (completed, work.count)
    }
}

// MARK: - Lesson Extensions

extension Lesson {
    /// Fetches all presentations (lesson assignments) of this lesson
    func fetchAllPresentations(from context: ModelContext) -> [LessonAssignment] {
        let lessonIDString = id.uuidString
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString },
            sortBy: [SortDescriptor(\.scheduledForDay, order: .reverse)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetches all work items related to this lesson
    func fetchAllWork(from context: ModelContext) -> [WorkModel] {
        let lessonIDString = id.uuidString
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { $0.lessonID == lessonIDString },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetches all practice sessions involving this lesson's work
    func fetchAllPracticeSessions(from context: ModelContext) -> [PracticeSession] {
        let workItems = fetchAllWork(from: context)
        let workIDs = Set(workItems.map { $0.id.uuidString })
        guard !workIDs.isEmpty else { return [] }
        
        // Fetch all practice sessions and filter in memory
        // This is necessary because SwiftData predicates don't support complex array operations
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let allSessions = (try? context.fetch(descriptor)) ?? []
        return allSessions.filter { session in
            session.workItemIDs.contains(where: { workIDs.contains($0) })
        }
    }
    
    /// Returns statistics about this lesson's usage
    func getLessonStats(from context: ModelContext) -> LessonStats {
        let presentations = fetchAllPresentations(from: context)
        let work = fetchAllWork(from: context)
        let practiceSessions = fetchAllPracticeSessions(from: context)
        
        let presentedCount = presentations.filter { $0.state == .presented }.count
        let completedWork = work.filter { $0.status == .complete }.count
        
        return LessonStats(
            totalPresentations: presentations.count,
            presentedCount: presentedCount,
            scheduledCount: presentations.filter { $0.state == .scheduled }.count,
            totalWorkItems: work.count,
            completedWorkItems: completedWork,
            activeWorkItems: work.filter { $0.status == .active }.count,
            totalPracticeSessions: practiceSessions.count,
            lastPresentedDate: presentations.compactMap { $0.presentedAt }.max()
        )
    }
}

// MARK: - PracticeSession Extensions

extension PracticeSession {
    /// Fetches all students who participated in this session
    func fetchStudents(from context: ModelContext) -> [Student] {
        guard !studentIDs.isEmpty else { return [] }
        
        // Convert string IDs to UUIDs for querying
        let uuids = studentIDs.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }
        
        // Fetch students by UUIDs
        let descriptor = FetchDescriptor<Student>(
            sortBy: [SortDescriptor(\.firstName)]
        )
        
        let allStudents = (try? context.fetch(descriptor)) ?? []
        return allStudents.filter { student in
            studentIDs.contains(student.id.uuidString)
        }
    }
    
    /// Fetches all work items practiced in this session
    func fetchWorkItems(from context: ModelContext) -> [WorkModel] {
        guard !workItemIDs.isEmpty else { return [] }
        
        // Convert string IDs to UUIDs for querying
        let uuids = workItemIDs.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }
        
        // Fetch all work items and filter in memory
        // This is necessary because SwiftData predicates don't support checking if UUID is in string array
        let descriptor = FetchDescriptor<WorkModel>()
        let allWork = (try? context.fetch(descriptor)) ?? []
        
        return allWork.filter { work in
            workItemIDs.contains(work.id.uuidString)
        }
    }
    
    /// Fetches the common lesson if all work items are for the same lesson
    func fetchCommonLesson(from context: ModelContext) -> Lesson? {
        let workItems = fetchWorkItems(from: context)
        guard !workItems.isEmpty else { return nil }
        
        let lessonIDs = Set(workItems.map { $0.lessonID })
        guard lessonIDs.count == 1,
              let lessonID = lessonIDs.first,
              let uuid = UUID(uuidString: lessonID) else { return nil }
        
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Supporting Types

struct LessonStats {
    let totalPresentations: Int
    let presentedCount: Int
    let scheduledCount: Int
    let totalWorkItems: Int
    let completedWorkItems: Int
    let activeWorkItems: Int
    let totalPracticeSessions: Int
    let lastPresentedDate: Date?
    
    var workCompletionRate: Double {
        guard totalWorkItems > 0 else { return 0 }
        return Double(completedWorkItems) / Double(totalWorkItems)
    }
}
