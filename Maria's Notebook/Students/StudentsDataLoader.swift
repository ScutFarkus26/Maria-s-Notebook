import Foundation
import CoreData

// MARK: - Students Data Loader

/// Loads and caches data for StudentsView.
enum StudentsDataLoader {

    // MARK: - Load Today's Attendance

    /// Loads today's attendance records.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Array of today's attendance records
    static func loadTodaysAttendance(context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        do {
            let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "CDAttendanceRecord")
        descriptor.predicate = NSPredicate(format: "date >= %@ AND date < %@", today as CVarArg, tomorrow as CVarArg)
        descriptor.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            return try context.fetch(descriptor)
        } catch {
            // Fallback: Fetch all and filter in memory
            let all = context.safeFetch(NSFetchRequest<CDAttendanceRecord>(entityName: "CDAttendanceRecord"))
            return all.filter { guard let d = $0.date else { return false }; return cal.isDate(d, inSameDayAs: today) }
        }
    }

    // MARK: - Load CDLesson Assignments

    /// Loads all lesson assignments for "days since last lesson" calculation.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Array of all lesson assignments
    static func loadLessonAssignments(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(NSFetchRequest<CDLessonAssignment>(entityName: "CDLessonAssignment"))
    }

    // MARK: - Load Lessons

    /// Loads all lessons as a dictionary for quick lookup.
    ///
    /// - Parameter context: Model context for fetching
    /// - Returns: Dictionary mapping lesson ID to CDLesson
    static func loadLessons(context: NSManagedObjectContext) -> [UUID: CDLesson] {
        let all = context.safeFetch(NSFetchRequest<CDLesson>(entityName: "CDLesson"))
        return Dictionary(all.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
