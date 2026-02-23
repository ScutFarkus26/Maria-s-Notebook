import Foundation
import SwiftData

// MARK: - Students Data Loader

/// Loads and caches data for StudentsView.
enum StudentsDataLoader {

    // MARK: - Load Today's Attendance

    /// Loads today's attendance records.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Array of today's attendance records
    static func loadTodaysAttendance(context: ModelContext) -> [AttendanceRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        do {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.date >= today && rec.date < tomorrow
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            return try context.fetch(descriptor)
        } catch {
            // Fallback: Fetch all and filter in memory
            let all = context.safeFetch(FetchDescriptor<AttendanceRecord>())
            return all.filter { cal.isDate($0.date, inSameDayAs: today) }
        }
    }

    // MARK: - Load Student Lessons

    /// Loads all student lessons for "days since last lesson" calculation.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Array of all student lessons
    static func loadStudentLessons(context: ModelContext) -> [StudentLesson] {
        context.safeFetch(FetchDescriptor<StudentLesson>())
    }

    // MARK: - Load Lessons

    /// Loads all lessons as a dictionary for quick lookup.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Dictionary mapping lesson ID to Lesson
    static func loadLessons(context: ModelContext) -> [UUID: Lesson] {
        let all = context.safeFetch(FetchDescriptor<Lesson>())
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
