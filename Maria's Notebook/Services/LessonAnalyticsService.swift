// LessonAnalyticsService.swift
// Shared query and grouping logic for lesson frequency and curriculum balance features.
// Fetches presented LessonAssignments, explodes multi-student assignments into individual
// per-student records joined with Lesson subject/group metadata.

import Foundation
import SwiftData

enum LessonAnalyticsService {

    // MARK: - Types

    /// A single presented lesson record resolved to one student + subject/group.
    struct PresentedRecord {
        let assignmentID: UUID
        let studentID: String        // UUID string
        let lessonID: UUID
        let subject: String
        let group: String
        let presentedAt: Date
    }

    // MARK: - Data Fetching

    /// Fetches all presented LessonAssignments in a date range and explodes them
    /// into per-student PresentedRecords joined with Lesson subject/group.
    ///
    /// Because `studentIDs` is JSON-encoded (CloudKit compatibility), we must fetch
    /// all assignments then filter in-memory — same pattern as ProgressDashboardViewModel.
    static func fetchPresentedRecords(
        context: ModelContext,
        from startDate: Date,
        to endDate: Date
    ) -> [PresentedRecord] {
        // PERF: Filter by state AND date range in the predicate to avoid loading entire history.
        // Previously loaded ALL presented assignments then filtered by date in memory.
        let presentedState = LessonAssignmentState.presented.rawValue
        let presented: [LessonAssignment] = context.safeFetch(
            FetchDescriptor<LessonAssignment>(
                predicate: #Predicate {
                    $0.stateRaw == presentedState &&
                    $0.presentedAt != nil &&
                    $0.presentedAt! >= startDate &&
                    $0.presentedAt! < endDate
                }
            )
        )

        // PERF: Fetch only lessons referenced by the filtered assignments.
        // Previously loaded ALL lessons for join.
        let neededLessonIDs = Set(presented.map(\.lessonID))
        let allLessons: [Lesson]
        if neededLessonIDs.isEmpty {
            allLessons = []
        } else {
            // SwiftData #Predicate can't capture local Set, so fetch all and filter
            allLessons = context.safeFetch(FetchDescriptor<Lesson>())
                .filter { neededLessonIDs.contains($0.id.uuidString) }
        }
        let lessonsByID: [String: Lesson] = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.id.uuidString, $0) }
        )

        // Explode: one record per (assignment × studentID)
        var records: [PresentedRecord] = []
        for la in presented {
            guard let lesson = lessonsByID[la.lessonID],
                  let presentedAt = la.presentedAt else { continue }
            for studentIDStr in la.studentIDs {
                records.append(PresentedRecord(
                    assignmentID: la.id,
                    studentID: studentIDStr,
                    lessonID: lesson.id,
                    subject: lesson.subject.trimmed(),
                    group: lesson.group.trimmed(),
                    presentedAt: presentedAt
                ))
            }
        }
        return records
    }

    // MARK: - Date Utilities

    /// Returns (mondayStart, nextMondayStart) for the school week containing `date`.
    /// Week runs Monday through Sunday (exclusive end) for query purposes.
    static func schoolWeekRange(for date: Date) -> (start: Date, end: Date) {
        let cal = AppCalendar.shared
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let daysFromMonday = (weekday + 5) % 7  // Mon=0, Tue=1, ..., Sun=6
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay)!
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        return (monday, nextMonday)
    }

    /// Returns the date offset by the given number of weeks from today.
    static func dateForWeekOffset(_ offset: Int) -> Date {
        AppCalendar.shared.date(byAdding: .weekOfYear, value: offset, to: Date()) ?? Date()
    }

    /// Formats a school week range as "Mar 9 – Mar 13, 2026" (Mon–Fri).
    static func weekLabel(for date: Date) -> String {
        let (monday, _) = schoolWeekRange(for: date)
        let friday = AppCalendar.shared.date(byAdding: .day, value: 4, to: monday)!
        let startStr = DateFormatters.shortMonthDay.string(from: monday)
        let endStr = DateFormatters.shortMonthDayYear.string(from: friday)
        return "\(startStr) – \(endStr)"
    }
}
