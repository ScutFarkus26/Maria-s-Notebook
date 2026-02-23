#if canImport(Testing)
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Performance Timing

/// Measures execution time and formats results for benchmark output.
struct PerformanceMeasurement {
    let elapsed: Double
    let unit: TimeUnit

    enum TimeUnit {
        case seconds
        case milliseconds

        var suffix: String {
            switch self {
            case .seconds: return "s"
            case .milliseconds: return "ms"
            }
        }
    }

    /// Measures execution time of a closure in seconds.
    static func measure(_ block: () throws -> Void) rethrows -> PerformanceMeasurement {
        let start = Date()
        try block()
        let elapsed = Date().timeIntervalSince(start)
        return PerformanceMeasurement(elapsed: elapsed, unit: .seconds)
    }

    /// Measures execution time of a closure in milliseconds.
    static func measureMilliseconds(_ block: () throws -> Void) rethrows -> PerformanceMeasurement {
        let start = Date()
        try block()
        let elapsed = Date().timeIntervalSince(start) * 1000
        return PerformanceMeasurement(elapsed: elapsed, unit: .milliseconds)
    }

    /// Formats the measurement for console output.
    func format(precision: Int = 3) -> String {
        let format = "%.\(precision)f"
        return String(format: format, elapsed) + unit.suffix
    }

    /// Prints benchmark result with emoji, name, target, and baseline.
    func printBenchmark(
        name: String,
        target: String,
        baseline: String,
        additionalStats: [String] = []
    ) {
        print("⏱️  \(name): \(format()) (target: \(target), baseline: \(baseline))")
        for stat in additionalStats {
            print("   📊 \(stat)")
        }
    }
}

// MARK: - Test Data Builders

/// Helper functions for creating test entities with consistent patterns.
struct TestDataBuilder {

    /// Creates an array of test students with consistent naming.
    static func createStudents(
        count: Int,
        context: ModelContext,
        namePrefix: String = "Student"
    ) -> [Student] {
        var students: [Student] = []
        for i in 0..<count {
            let student = makeTestStudent(
                firstName: namePrefix,
                lastName: "\(i)",
                manualOrder: i
            )
            context.insert(student)
            students.append(student)
        }
        return students
    }

    /// Creates an array of test lessons with consistent naming.
    static func createLessons(
        count: Int,
        context: ModelContext,
        namePrefix: String = "Lesson",
        subjectPrefix: String? = nil
    ) -> [Lesson] {
        var lessons: [Lesson] = []
        for i in 0..<count {
            let subject = subjectPrefix.map { "\($0) \(i / 20)" }
            let lesson = makeTestLesson(name: "\(namePrefix) \(i)", subject: subject)
            context.insert(lesson)
            lessons.append(lesson)
        }
        return lessons
    }

    /// Creates an array of test work items with varied statuses.
    static func createWorkItems(
        count: Int,
        context: ModelContext,
        students: [Student],
        includeParticipants: Bool = true
    ) throws -> [WorkModel] {
        var workItems: [WorkModel] = []
        let statuses: [WorkStatus] = [.active, .review, .complete]
        let kinds: [WorkKind] = [.practiceLesson, .research, .followUpAssignment, .report]

        for i in 0..<count {
            let status = statuses[i % statuses.count]
            let kind = kinds[i % kinds.count]
            let student = students[i % students.count]

            let dueDate: Date? = (i % 2 == 0) ?
                Date().addingTimeInterval(Double(i - count / 2) * 86400) : nil

            let work = makeTestWorkModel(
                title: "Work Item \(i)",
                kind: kind,
                status: status,
                dueAt: dueDate,
                studentID: student.id.uuidString
            )
            context.insert(work)
            workItems.append(work)

            if includeParticipants {
                let participant = WorkParticipantEntity(
                    studentID: student.id,
                    work: work
                )
                context.insert(participant)
            }
        }

        return workItems
    }

    /// Creates attendance records for a date range.
    static func createAttendanceRecords(
        students: [Student],
        dayCount: Int,
        context: ModelContext,
        recordProbability: Double = 0.8
    ) {
        let startDate = AppCalendar.startOfDay(Date()).addingTimeInterval(-Double(dayCount) * 86400)
        let statuses: [AttendanceStatus] = [.present, .absent, .tardy, .leftEarly]

        for dayOffset in 0..<dayCount {
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)

            for (index, student) in students.enumerated() {
                // Deterministic record creation based on index
                let shouldCreate = Double((dayOffset * students.count + index) % 100) / 100.0 < recordProbability
                if shouldCreate {
                    let status = statuses[(dayOffset + index) % statuses.count]
                    let record = makeTestAttendanceRecord(
                        studentID: student.id,
                        date: date,
                        status: status
                    )
                    context.insert(record)
                }
            }
        }
    }

    /// Creates student lessons distributed across a date range.
    static func createStudentLessons(
        count: Int,
        students: [Student],
        lessons: [Lesson],
        dateRange: (start: Date, days: Int),
        context: ModelContext
    ) {
        for i in 0..<count {
            let student = students[i % students.count]
            let lesson = lessons[i % lessons.count]
            let dayOffset = i % max(dateRange.days, 1)
            let date = dateRange.start.addingTimeInterval(Double(dayOffset) * 86400)

            let sl = StudentLesson(
                lesson: lesson,
                students: [student],
                scheduledFor: date,
                givenAt: (i % 3 == 0) ? date : nil,
                isPresented: (i % 4 == 0)
            )
            context.insert(sl)
        }
    }

    /// Creates notes with varied scopes for students.
    static func createNotes(
        count: Int,
        students: [Student],
        context: ModelContext
    ) {
        for i in 0..<count {
            let student = students[i % students.count]
            let note = Note(
                body: "Test note \(i) with some content about student progress",
                scope: .student(student.id)
            )
            context.insert(note)
        }
    }

    /// Creates notes with mixed scopes (.all, .student, .students) for scope query benchmarks.
    static func createMixedScopeNotes(
        count: Int,
        students: [Student],
        context: ModelContext
    ) {
        for i in 0..<count {
            let scope: NoteScope
            switch i % 5 {
            case 0:
                // 20% .all scope
                scope = .all
            case 1, 2:
                // 40% single student scope
                let student = students[i % students.count]
                scope = .student(student.id)
            default:
                // 40% multi-student scope
                let s1 = students[i % students.count]
                let s2 = students[(i + 1) % students.count]
                scope = .students([s1.id, s2.id])
            }

            let note = Note(
                body: "Mixed scope note \(i) with content for benchmarking",
                scope: scope
            )
            context.insert(note)
        }
    }
}

// MARK: - Performance Baseline Documentation

/*
 PERFORMANCE BASELINES
 =====================

 Benchmarked on: Apple Silicon Mac (M1/M2/M3)
 SwiftData: Latest version, in-memory containers

 Expected Results:

 1. Today View Load (30 students, 100 lessons, 200 SLs)
    Target: < 100ms | scheduledForDay predicate + cache building

 2. Work List Query (30 students, 500 work items)
    Target: < 150ms | statusRaw string predicate + participant loading

 3. Attendance Grid (30 students × 180 days = ~4,300 records)
    Target: < 200ms | Date range query + grid structure building

 4. StudentLesson In-Memory Filter (20 students, 2000 SLs)
    Target: < 300ms | Full fetch + in-memory filter (studentIDs is @Transient)

 5. Batch Student Lookup (30 students, 200 work items)
    Target: < 200ms | Dictionary-based participant resolution

 6. Note Scope Query (10 students, 500 notes)
    Target: < 100ms | Dual-query: searchIndexStudentID + scopeIsAll + NoteStudentLink

 7. WorkCheckIn Scheduled Query (300 work items, ~600 check-ins)
    Target: < 100ms | statusRaw + date predicate, grouped by work

 REGRESSION THRESHOLDS
 - Green: ±10% of baseline (normal variance)
 - Yellow: 10-20% regression (investigate if consistent)
 - Red: >20% regression (requires immediate attention)

 OPTIMIZATION PRIORITIES
 High Impact: Today View, StudentLesson filter, Work list
 Medium Impact: Attendance grid, Note scope query
 Low Impact: Batch lookup, WorkCheckIn query

 RUNNING BENCHMARKS
 From Xcode: Test Navigator (⌘6) → "Performance Benchmarks" → ▶️
 From CLI: swift test --filter PerformanceBenchmarks
 */

#endif
