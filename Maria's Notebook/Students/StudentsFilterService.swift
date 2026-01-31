import Foundation
import SwiftData

// MARK: - Students Filter Service

/// Service for computing filtered and sorted student lists.
enum StudentsFilterService {

    // MARK: - Compute Hidden Test Student IDs

    /// Computes the set of student IDs that should be hidden based on test student settings.
    ///
    /// - Parameters:
    ///   - students: All students
    ///   - showTestStudents: Whether to show test students
    ///   - testStudentNamesRaw: Raw string of test student names
    /// - Returns: Set of UUIDs for students that should be hidden
    static func computeHiddenTestStudentIDs(
        students: [Student],
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) -> Set<UUID> {
        guard !showTestStudents else { return [] }

        let lower = testStudentNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { $0.trimmed() }.filter { !$0.isEmpty }
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
        attendanceRecords: [AttendanceRecord],
        hiddenTestStudentIDs: Set<UUID>
    ) -> Set<UUID> {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        let todaysPresent = attendanceRecords.filter { rec in
            cal.isDate(rec.date, inSameDayAs: today) && (rec.status == .present || rec.status == .tardy)
        }

        // CloudKit compatibility: Convert String studentIDs to UUIDs
        var ids = Set(todaysPresent.compactMap { UUID(uuidString: $0.studentID) })
        ids.subtract(hiddenTestStudentIDs)
        return ids
    }

    // MARK: - Compute Days Since Last Presentation

    /// Computes days since last presentation for each student using LessonPresentation records.
    ///
    /// - Parameters:
    ///   - students: All students
    ///   - modelContext: Model context for fetching presentations and school days calculation
    ///   - calendar: Calendar for date calculations
    /// - Returns: Dictionary mapping student ID to days since last presentation (-1 if no presentation)
    static func computeDaysSinceLastPresentation(
        students: [Student],
        modelContext: ModelContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Fetch all LessonPresentation records
        let descriptor = FetchDescriptor<LessonPresentation>(
            sortBy: [SortDescriptor(\LessonPresentation.presentedAt, order: .reverse)]
        )
        let presentations = modelContext.safeFetch(descriptor)

        // Fetch lessons to exclude (parsha lessons)
        let lessonsDescriptor = FetchDescriptor<Lesson>()
        let allLessons = modelContext.safeFetch(lessonsDescriptor)
        let excludedLessonIDs: Set<String> = {
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id.uuidString }
            return Set(ids)
        }()

        // Filter out excluded lessons
        let relevantPresentations = presentations.filter { !excludedLessonIDs.contains($0.lessonID) }

        // Build a map of student ID to most recent presentation date
        var lastDateByStudent: [UUID: Date] = [:]
        for lp in relevantPresentations {
            guard let studentUUID = UUID(uuidString: lp.studentID) else { continue }
            let when = lp.presentedAt
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
            if let lastDate = lastDateByStudent[student.id] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: lastDate,
                    asOf: Date(),
                    using: modelContext,
                    calendar: calendar
                )
                result[student.id] = days
            } else {
                result[student.id] = -1 // No presentation found
            }
        }

        return result
    }
}
