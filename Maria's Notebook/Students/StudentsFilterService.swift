import Foundation
import CoreData

// MARK: - Students Filter Service

/// Service for computing filtered and sorted student lists.
enum StudentsFilterService {

    // MARK: - Compute Hidden Test CDStudent IDs

    /// Computes the set of student IDs that should be hidden based on test student settings.
    ///
    /// - Parameters:
    ///   - students: All students
    ///   - showTestStudents: Whether to show test students
    ///   - testStudentNamesRaw: Raw string of test student names
    /// - Returns: Set of UUIDs for students that should be hidden
    static func computeHiddenTestStudentIDs(
        students: [CDStudent],
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) -> Set<UUID> {
        guard !showTestStudents else { return [] }

        let lower = testStudentNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { String($0).trimmed() }.filter { !$0.isEmpty }
        let hiddenNames = Set(tokens)

        let ids = students.compactMap { s -> UUID? in
            let name = s.fullName.normalizedForComparison()
            return hiddenNames.contains(name) ? s.id : nil
        }

        return Set(ids)
    }

    // MARK: - Compute Present Now IDs

    /// Computes the set of student IDs that are currently present.
    ///
    /// - Parameters:
    ///   - attendanceRecords: Today's attendance records
    ///   - hiddenTestStudentIDs: IDs to exclude from result
    /// - Returns: Set of present student UUIDs
    static func computePresentNowIDs(
        attendanceRecords: [CDAttendanceRecord],
        hiddenTestStudentIDs: Set<UUID>
    ) -> Set<UUID> {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        let todaysPresent = attendanceRecords.filter { rec in
            guard let d = rec.date else { return false }; return cal.isDate(d, inSameDayAs: today) && (rec.status == .present || rec.status == .tardy)
        }

        // CloudKit compatibility: Convert String studentIDs to UUIDs
        var ids = Set(todaysPresent.compactMap { UUID(uuidString: $0.studentID) })
        ids.subtract(hiddenTestStudentIDs)
        return ids
    }

    // MARK: - Compute Days Since Last Presentation

    /// Computes days since last presentation for each student using CDLessonPresentation records.
    ///
    /// - Parameters:
    ///   - students: All students
    ///   - viewContext: Model context for fetching presentations and school days calculation
    ///   - calendar: Calendar for date calculations
    /// - Returns: Dictionary mapping student ID to days since last presentation (-1 if no presentation)
    static func computeDaysSinceLastPresentation(
        students: [CDStudent],
        viewContext: NSManagedObjectContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Fetch all CDLessonPresentation records
        let descriptor: NSFetchRequest<CDLessonPresentation> = NSFetchRequest(entityName: "LessonPresentation")
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonPresentation.presentedAt, ascending: false)]
        let presentations = viewContext.safeFetch(descriptor)

        // Fetch lessons to exclude (parsha lessons)
        let lessonsDescriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
        let allLessons = viewContext.safeFetch(lessonsDescriptor)
        let excludedLessonIDs: Set<String> = {
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.compactMap { $0.id?.uuidString }
            return Set(ids)
        }()

        // Filter out excluded lessons
        let relevantPresentations = presentations.filter { !excludedLessonIDs.contains($0.lessonID) }

        // Build a map of student ID to most recent presentation date
        var lastDateByStudent: [UUID: Date] = [:]
        for lp in relevantPresentations {
            guard let studentUUID = UUID(uuidString: lp.studentID) else { continue }
            guard let when = lp.presentedAt else { continue }
            if let existing = lastDateByStudent[studentUUID] {
                if when > existing {
                    lastDateByStudent[studentUUID] = when
                }
            } else {
                lastDateByStudent[studentUUID] = when
            }
        }

        // Compute days since last presentation for each student
        var result: [UUID: Int] = [:]
        for student in students {
            guard let studentID = student.id else { continue }
            if let lastDate = lastDateByStudent[studentID] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: lastDate,
                    asOf: Date(),
                    using: viewContext,
                    calendar: calendar
                )
                result[studentID] = days
            } else {
                result[studentID] = -1 // No presentation found
            }
        }

        return result
    }
}
