// TEMPORARILY DISABLED: This file supports PerformanceBenchmarks.swift
#if false && canImport(Testing)
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
        let workTypes: [WorkModel.WorkType] = [.practice, .research, .followUp, .report]

        for i in 0..<count {
            let status = statuses.randomElement()!
            let workType = workTypes.randomElement()!
            let student = students.randomElement()!

            let dueDate: Date? = Bool.random() ?
                Date().addingTimeInterval(Double.random(in: -10...10) * 86400) : nil

            let work = makeTestWorkModel(
                title: "Work Item \(i)",
                workType: workType,
                status: status,
                dueAt: dueDate,
                studentID: student.id.uuidString
            )
            context.insert(work)
            workItems.append(work)

            // Add participant if requested
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
        let startDate = Date().startOfDay.addingTimeInterval(-Double(dayCount) * 86400)
        let statuses: [AttendanceStatus] = [.present, .absent, .tardy, .leftEarly]

        for dayOffset in 0..<dayCount {
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)

            for student in students {
                // Create record with given probability (default 80%)
                if Double.random(in: 0...1) < recordProbability {
                    let status = statuses.randomElement()!
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
        for _ in 0..<count {
            let student = students.randomElement()!
            let lesson = lessons.randomElement()!
            let randomDayOffset = Int.random(in: 0...dateRange.days)
            let date = dateRange.start.addingTimeInterval(Double(randomDayOffset) * 86400)

            let sl = StudentLesson(
                lesson: lesson,
                students: [student],
                scheduledFor: date,
                givenAt: Bool.random() ? date : nil,
                isPresented: Bool.random()
            )
            context.insert(sl)
        }
    }

    /// Creates notes for students.
    static func createNotes(
        count: Int,
        students: [Student],
        context: ModelContext
    ) {
        for i in 0..<count {
            let student = students.randomElement()!
            let note = Note(
                body: "Test note \(i) with some content about student progress",
                scope: .student(student.id)
            )
            context.insert(note)
        }
    }
}

// MARK: - Bulk DTO Conversion

/// Helpers for batch DTO conversions in backup tests.
struct DTOBatchConverter {

    /// Converts an array of students to DTOs.
    static func convertStudents(_ students: [Student]) -> [StudentDTO] {
        students.map { BackupDTOTransformers.toDTO($0) }
    }

    /// Converts an array of lessons to DTOs.
    static func convertLessons(_ lessons: [Lesson]) -> [LessonDTO] {
        lessons.map { BackupDTOTransformers.toDTO($0) }
    }

    /// Converts an array of student lessons to DTOs.
    static func convertStudentLessons(_ studentLessons: [StudentLesson]) -> [StudentLessonDTO] {
        studentLessons.compactMap { BackupDTOTransformers.toDTO($0) }
    }

    /// Converts an array of attendance records to DTOs.
    static func convertAttendance(_ records: [AttendanceRecord]) -> [AttendanceRecordDTO] {
        records.compactMap { BackupDTOTransformers.toDTO($0) }
    }

    /// Converts an array of notes to DTOs.
    static func convertNotes(_ notes: [Note]) -> [NoteDTO] {
        notes.map { BackupDTOTransformers.toDTO($0) }
    }

    /// Creates student lesson DTOs from existing student and lesson DTOs.
    static func createStudentLessonDTOs(
        count: Int,
        studentDTOs: [StudentDTO],
        lessonDTOs: [LessonDTO],
        dateRange: (days: Int)
    ) -> [StudentLessonDTO] {
        var dtos: [StudentLessonDTO] = []

        for _ in 0..<count {
            let studentDTO = studentDTOs.randomElement()!
            let lessonDTO = lessonDTOs.randomElement()!
            let date = Date().addingTimeInterval(Double.random(in: -Double(dateRange.days)...Double(dateRange.days)) * 86400)

            let sl = StudentLesson(
                lessonID: lessonDTO.id.uuidString,
                studentIDs: [studentDTO.id.uuidString],
                scheduledFor: date
            )
            if let dto = BackupDTOTransformers.toDTO(sl) {
                dtos.append(dto)
            }
        }

        return dtos
    }

    /// Creates attendance DTOs from existing student DTOs.
    static func createAttendanceDTOs(
        count: Int,
        studentDTOs: [StudentDTO],
        dayRange: Int
    ) -> [AttendanceRecordDTO] {
        var dtos: [AttendanceRecordDTO] = []
        let startDate = Date().startOfDay.addingTimeInterval(-Double(dayRange) * 86400)

        for _ in 0..<count {
            let studentDTO = studentDTOs.randomElement()!
            let dayOffset = Int.random(in: 0...dayRange)
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)

            let record = AttendanceRecord(
                id: UUID(),
                studentID: studentDTO.id,
                date: date,
                status: .present
            )
            if let dto = BackupDTOTransformers.toDTO(record) {
                dtos.append(dto)
            }
        }

        return dtos
    }

    /// Creates work DTOs from existing student DTOs.
    static func createWorkDTOs(
        count: Int,
        studentDTOs: [StudentDTO]
    ) -> [WorkDTO] {
        var dtos: [WorkDTO] = []

        for i in 0..<count {
            let studentDTO = studentDTOs.randomElement()!
            let workDTO = WorkDTO(
                id: UUID(),
                title: "Work \(i)",
                studentIDs: [studentDTO.id],
                workType: "Practice",
                studentLessonID: nil,
                notes: "",
                createdAt: Date(),
                completedAt: nil,
                participants: []
            )
            dtos.append(workDTO)
        }

        return dtos
    }

    /// Creates note DTOs from existing student DTOs.
    static func createNoteDTOs(
        count: Int,
        studentDTOs: [StudentDTO]
    ) -> [NoteDTO] {
        var dtos: [NoteDTO] = []

        for i in 0..<count {
            let studentDTO = studentDTOs.randomElement()!
            let note = Note(
                body: "Test note \(i)",
                scope: .student(studentDTO.id)
            )
            dtos.append(BackupDTOTransformers.toDTO(note))
        }

        return dtos
    }
}

// MARK: - Container Creation

/// Helper for creating test containers.
struct TestContainerFactory {

    /// Creates an in-memory test container with all app models.
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: AppSchema.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: AppSchema.schema,
            configurations: [config]
        )
    }
}

// MARK: - Performance Baseline Documentation

/*
 PERFORMANCE BASELINES (Phase 5)
 ================================

 Benchmarked on: Apple Silicon Mac (M1/M2/M3)
 SwiftData: Latest version as of Phase 5

 Expected Results:

 1. App Startup (20 students, 50 lessons, 20 work items)
    Time: ~1.5s ± 0.3s | Includes: Container init + initial queries

 2. Today View Load (1000 lessons)
    Time: ~75ms ± 15ms | Includes: Date predicate + relationship lookups + cache building

 3. Work List Query (500 items)
    Time: ~120ms ± 20ms | Includes: Status filter + sorting + participant loading

 4. Attendance Grid (30 students × 180 days = 5,400 records)
    Time: ~160ms ± 30ms | Includes: Date range query + grid structure building

 5. Backup Export (10k entities)
    Time: ~8s ± 2s | Includes: Full fetch + DTO conversion

 6. Backup Restore (10k entities)
    Time: ~12s ± 3s | Includes: Entity creation + batch insert + save

 7. String ID Lookup (500 student lessons)
    Time: ~60ms | Note: 2-3x slower than relationship traversal

 8. Batch Query (100 work items)
    Time: ~30ms | Note: 10-13x faster than N+1 pattern

 REGRESSION THRESHOLDS
 - Green: ±10% of baseline (normal variance)
 - Yellow: 10-20% regression (investigate if consistent)
 - Red: >20% regression (requires immediate attention)

 OPTIMIZATION PRIORITIES
 High Impact: Today View, Work list, String ID vs relationship
 Medium Impact: Attendance grid, App startup
 Low Impact: Backup operations (infrequent)

 INDEX RECOMMENDATIONS
 Critical: StudentLesson.scheduledFor/givenAt, WorkModel.status, AttendanceRecord.date/studentID
 Optional: Note.searchIndexStudentID, StudentTrackEnrollment IDs

 RUNNING BENCHMARKS
 From Xcode: Test Navigator (⌘6) → "Performance Benchmarks" → ▶️
 From CLI: swift test --filter PerformanceBenchmarks

 PROFILING
 Use Instruments (Time Profiler, Allocations, System Trace) for deep analysis.
 Right-click test → "Profile in Instruments"
 */

#endif
