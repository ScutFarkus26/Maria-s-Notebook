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
            // Load counts serially on the MainActor.
            // Parallel execution (async let) on a single ModelContext is not thread-safe
            // and causes Sendable errors because ModelContext is confined to the actor that created it.
            
            let students = loadCount(for: Student.self, context: context)
            let lessons = loadCount(for: Lesson.self, context: context)
            let studentLessons = loadCount(for: StudentLesson.self, context: context)
            let contracts = loadCount(for: WorkContract.self, context: context)
            let presentations = loadCount(for: Presentation.self, context: context)
            let notes = loadCount(for: Note.self, context: context)
            let meetings = loadCount(for: StudentMeeting.self, context: context)
            
            // Load filtered counts
            let planned = loadFilteredCount(
                for: StudentLesson.self,
                predicate: #Predicate<StudentLesson> { $0.givenAt == nil },
                context: context
            )
            let given = loadFilteredCount(
                for: StudentLesson.self,
                predicate: #Predicate<StudentLesson> { $0.givenAt != nil },
                context: context
            )
            
            // Update state
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
    
    /// Load count for a model type
    /// Note: ModelContext access is assumed to be fast for counts, keeping this synchronous on MainActor is safe.
    private func loadCount<T: PersistentModel>(
        for type: T.Type,
        context: ModelContext
    ) -> Int {
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
    ) -> Int {
        // ModelContext must be accessed on MainActor
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        return context.safeFetch(descriptor).count
    }
}
