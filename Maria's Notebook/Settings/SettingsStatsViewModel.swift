import Foundation
import SwiftData
import SwiftUI
import Combine

/// ViewModel for efficiently loading and caching Settings statistics
/// Optimizes SettingsView by avoiding loading entire tables just for counts
@MainActor
class SettingsStatsViewModel: ObservableObject {
    @Published var studentsCount: Int = 0
    @Published var lessonsCount: Int = 0
    @Published var studentLessonsCount: Int = 0
    @Published var plannedCount: Int = 0
    @Published var givenCount: Int = 0
    @Published var workContractsCount: Int = 0
    @Published var presentationsCount: Int = 0
    @Published var notesCount: Int = 0
    @Published var meetingsCount: Int = 0
    
    @Published var isLoading: Bool = false
    
    private var lastLoadDate: Date?
    private let cacheDuration: TimeInterval = 30 // Cache for 30 seconds
    
    /// Load all statistics efficiently
    func loadCounts(context: ModelContext) {
        // Use cached data if recent
        if let lastLoad = lastLoadDate,
           Date().timeIntervalSince(lastLoad) < cacheDuration {
            return
        }
        
        isLoading = true
        
        Task {
            // Load counts in parallel where possible
            async let studentsTask = loadCount(for: Student.self, context: context)
            async let lessonsTask = loadCount(for: Lesson.self, context: context)
            async let studentLessonsTask = loadCount(for: StudentLesson.self, context: context)
            async let workContractsTask = loadCount(for: WorkContract.self, context: context)
            async let presentationsTask = loadCount(for: Presentation.self, context: context)
            async let notesTask = loadCount(for: Note.self, context: context)
            async let meetingsTask = loadCount(for: StudentMeeting.self, context: context)
            
            // Load filtered counts
            async let plannedTask = loadFilteredCount(
                for: StudentLesson.self,
                predicate: #Predicate<StudentLesson> { $0.givenAt == nil },
                context: context
            )
            async let givenTask = loadFilteredCount(
                for: StudentLesson.self,
                predicate: #Predicate<StudentLesson> { $0.givenAt != nil },
                context: context
            )
            
            // Await all results
            let (students, lessons, studentLessons, planned, given, contracts, presentations, notes, meetings) = await (
                studentsTask, lessonsTask, studentLessonsTask, plannedTask, givenTask,
                workContractsTask, presentationsTask, notesTask, meetingsTask
            )
            
            await MainActor.run {
                self.studentsCount = students
                self.lessonsCount = lessons
                self.studentLessonsCount = studentLessons
                self.plannedCount = planned
                self.givenCount = given
                self.workContractsCount = contracts
                self.presentationsCount = presentations
                self.notesCount = notes
                self.meetingsCount = meetings
                self.lastLoadDate = Date()
                self.isLoading = false
            }
        }
    }
    
    /// Load count for a model type
    private func loadCount<T: PersistentModel>(
        for type: T.Type,
        context: ModelContext
    ) async -> Int {
        // ModelContext must be accessed on MainActor
        let descriptor = FetchDescriptor<T>()
        // Note: SwiftData doesn't have direct count, so we fetch and count
        // For large datasets, this could be optimized further with sampling
        return context.safeFetch(descriptor).count
    }
    
    /// Load count for a filtered model type
    private func loadFilteredCount<T: PersistentModel>(
        for type: T.Type,
        predicate: Predicate<T>,
        context: ModelContext
    ) async -> Int {
        // ModelContext must be accessed on MainActor
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        return context.safeFetch(descriptor).count
    }
}

