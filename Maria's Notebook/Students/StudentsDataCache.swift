import Foundation
import SwiftData

/// Manages cached data for the students view, loading data on-demand
/// based on the current mode and filters.
///
/// This extracts the caching logic from StudentsView for better
/// testability and separation of concerns.
@MainActor
final class StudentsDataCache {
    // MARK: - Cached Data

    /// Today's attendance records
    private(set) var attendanceRecords: [AttendanceRecord] = []

    /// Student lessons (currently unused but retained for future use)
    private(set) var studentLessons: [StudentLesson] = []

    /// Lessons by ID (currently unused but retained for future use)
    private(set) var lessons: [UUID: Lesson] = [:]

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
    ///   - modelContext: The model context for database queries
    ///   - calendar: The calendar for date calculations
    func loadDataOnDemand(
        mode: StudentMode,
        students: [Student],
        modelContext: ModelContext,
        calendar: Calendar
    ) async {
        guard mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson else {
            // Clear caches when not in roster mode
            clearCaches()
            return
        }

        // Load today's attendance records using the data loader
        attendanceRecords = StudentsDataLoader.loadTodaysAttendance(context: modelContext)

        // Load days since last lesson only when in lastLesson mode or roster mode
        // (roster mode needs it for the list row display)
        if mode == .lastLesson || mode == .roster {
            daysSinceLastLesson = StudentsFilterService.computeDaysSinceLastPresentation(
                students: students,
                modelContext: modelContext,
                calendar: calendar
            )
        } else {
            daysSinceLastLesson = [:]
        }

        // Clear studentLessons cache (no longer needed for lastLesson mode)
        studentLessons = []
        lessons = [:]
    }

    /// Clears all cached data
    func clearCaches() {
        attendanceRecords = []
        studentLessons = []
        lessons = [:]
        daysSinceLastLesson = [:]
    }
}
