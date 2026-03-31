import Foundation
import CoreData

/// Manages cached data for the students view, loading data on-demand
/// based on the current mode and filters.
///
/// This extracts the caching logic from StudentsView for better
/// testability and separation of concerns.
@MainActor
final class StudentsDataCache {
    // MARK: - Cached Data

    /// Today's attendance records
    private(set) var attendanceRecords: [CDAttendanceRecord] = []

    /// CDLesson assignments (currently unused but retained for future use)
    private(set) var lessonAssignments: [CDLessonAssignment] = []

    /// Lessons by ID (currently unused but retained for future use)
    private(set) var lessons: [UUID: CDLesson] = [:]

    /// Days since last lesson presentation, keyed by student ID
    private(set) var daysSinceLastLesson: [UUID: Int] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Loading

    /// Loads data on-demand based on current mode.
    ///
    /// - Parameters:
    ///   - mode: The current student view mode
    ///   - students: The list of students to compute data for
    ///   - viewContext: The model context for database queries
    ///   - calendar: The calendar for date calculations
    func loadDataOnDemand(
        mode: StudentMode,
        students: [CDStudent],
        viewContext: NSManagedObjectContext,
        calendar: Calendar
    ) async {
        // Load today's attendance records using the data loader
        attendanceRecords = StudentsDataLoader.loadTodaysAttendance(context: viewContext)

        daysSinceLastLesson = [:]

        // Clear lesson assignments cache
        lessonAssignments = []
        lessons = [:]
    }

    /// Clears all cached data
    func clearCaches() {
        attendanceRecords = []
        lessonAssignments = []
        lessons = [:]
        daysSinceLastLesson = [:]
    }
}
