#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Configurations

private enum BenchmarkContainers {
    static let todayViewTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self,
        AttendanceRecord.self, WorkModel.self,
        WorkParticipantEntity.self, WorkCheckIn.self,
        WorkStep.self, WorkCompletionRecord.self,
        Note.self, NoteStudentLink.self,
        LessonPresentation.self,
    ]

    static let workQueryTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, WorkModel.self,
        WorkParticipantEntity.self, WorkCheckIn.self,
        WorkStep.self, WorkCompletionRecord.self,
        Note.self, NoteStudentLink.self,
    ]

    static let attendanceTypes: [any PersistentModel.Type] = [
        Student.self, AttendanceRecord.self,
        Note.self, NoteStudentLink.self,
    ]

    static let studentLessonTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self,
        Note.self, NoteStudentLink.self,
        LessonPresentation.self,
    ]

    static let noteQueryTypes: [any PersistentModel.Type] = [
        Student.self, Note.self, NoteStudentLink.self,
        Lesson.self, StudentLesson.self,
        WorkModel.self, WorkParticipantEntity.self,
        WorkStep.self, WorkCompletionRecord.self,
        LessonPresentation.self,
    ]

    static let checkInTypes: [any PersistentModel.Type] = [
        Student.self, WorkModel.self,
        WorkParticipantEntity.self, WorkCheckIn.self,
        WorkStep.self, WorkCompletionRecord.self,
        Note.self, NoteStudentLink.self,
    ]
}

// MARK: - Performance Benchmarks

@Suite("Performance Benchmarks", .serialized)
@MainActor
struct PerformanceBenchmarks {

    // MARK: - 1. Today View Load

    @Test("Today View Load — scheduledForDay predicate + cache building")
    func todayViewLoadPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.todayViewTypes)
        let context = ModelContext(container)

        // Seed: 30 students, 100 lessons, 200 StudentLessons spread across 30 days
        let students = TestDataBuilder.createStudents(count: 30, context: context)
        let lessons = TestDataBuilder.createLessons(count: 100, context: context)
        let today = AppCalendar.startOfDay(Date())
        TestDataBuilder.createStudentLessons(
            count: 200,
            students: students,
            lessons: lessons,
            dateRange: (start: today.addingTimeInterval(-15 * 86400), days: 30),
            context: context
        )
        try context.save()

        // Measure: fetch today's lessons + build cache (mirrors TodayDataFetcher)
        let ms = try PerformanceMeasurement.measureMilliseconds {
            let nextDay = today.addingTimeInterval(86400)
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= today && sl.scheduledForDay < nextDay
                }
            )
            let dayLessons = try context.fetch(descriptor)

            // Build lookup caches (production pattern)
            var lessonCache: [String: Lesson] = [:]
            for sl in dayLessons {
                let lid = sl.lessonID
                if lessonCache[lid] == nil {
                    lessonCache[lid] = sl.lesson
                }
            }
            // Prevent optimizer from eliding
            _ = dayLessons.count + lessonCache.count
        }

        ms.printBenchmark(
            name: "Today View Load",
            target: "< 100ms",
            baseline: "~75ms"
        )
        #expect(ms.elapsed < 500, "Today View Load exceeded 500ms threshold")
    }

    // MARK: - 2. Work List Query

    @Test("Work List Query — statusRaw predicate + participant loading")
    func workListQueryPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.workQueryTypes)
        let context = ModelContext(container)

        // Seed: 30 students, 500 work items with participants
        let students = TestDataBuilder.createStudents(count: 30, context: context)
        _ = try TestDataBuilder.createWorkItems(
            count: 500,
            context: context,
            students: students,
            includeParticipants: true
        )
        try context.save()

        // Measure: fetch open work + load participants (mirrors DataQueryService)
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue

        let ms = try PerformanceMeasurement.measureMilliseconds {
            var descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate { w in
                    w.statusRaw == activeRaw || w.statusRaw == reviewRaw
                },
                sortBy: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            let workItems = try context.fetch(descriptor)

            // Resolve participants per work item (production pattern)
            var participantsByWork: [UUID: [String]] = [:]
            for work in workItems {
                let pIDs = (work.participants ?? []).map { $0.studentID }
                participantsByWork[work.id] = pIDs
            }
            _ = workItems.count + participantsByWork.count
        }

        ms.printBenchmark(
            name: "Work List Query",
            target: "< 150ms",
            baseline: "~120ms"
        )
        #expect(ms.elapsed < 600, "Work List Query exceeded 600ms threshold")
    }

    // MARK: - 3. Attendance Grid

    @Test("Attendance Grid — date range query + grid building")
    func attendanceGridPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.attendanceTypes)
        let context = ModelContext(container)

        // Seed: 30 students × 180 days = ~4,300 records (80% density)
        let students = TestDataBuilder.createStudents(count: 30, context: context)
        TestDataBuilder.createAttendanceRecords(
            students: students,
            dayCount: 180,
            context: context,
            recordProbability: 0.8
        )
        try context.save()

        // Measure: date range fetch + grid structure building (mirrors AttendanceViewModel)
        let startDate = AppCalendar.startOfDay(Date()).addingTimeInterval(-180 * 86400)
        let endDate = AppCalendar.startOfDay(Date())

        let ms = try PerformanceMeasurement.measureMilliseconds {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { record in
                    record.date >= startDate && record.date <= endDate
                },
                sortBy: [SortDescriptor(\.date), SortDescriptor(\.studentID)]
            )
            let records = try context.fetch(descriptor)

            // Build grid keyed by studentID → date → record
            var grid: [String: [Date: AttendanceRecord]] = [:]
            for record in records {
                grid[record.studentID, default: [:]][record.date] = record
            }
            _ = records.count + grid.count
        }

        ms.printBenchmark(
            name: "Attendance Grid",
            target: "< 200ms",
            baseline: "~160ms"
        )
        #expect(ms.elapsed < 800, "Attendance Grid exceeded 800ms threshold")
    }

    // MARK: - 4. StudentLesson In-Memory Filter

    @Test("StudentLesson In-Memory Filter — full fetch + filter (@Transient studentIDs)")
    func studentLessonInMemoryFilterPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.studentLessonTypes)
        let context = ModelContext(container)

        // Seed: 20 students, 50 lessons, 2000 StudentLessons
        let students = TestDataBuilder.createStudents(count: 20, context: context)
        let lessons = TestDataBuilder.createLessons(count: 50, context: context)
        let today = AppCalendar.startOfDay(Date())
        TestDataBuilder.createStudentLessons(
            count: 2000,
            students: students,
            lessons: lessons,
            dateRange: (start: today.addingTimeInterval(-365 * 86400), days: 365),
            context: context
        )
        try context.save()

        // Measure: fetch ALL then filter in memory
        // This is the production pattern because studentIDs is @Transient
        let targetIDString = students[0].id.uuidString

        let ms = try PerformanceMeasurement.measureMilliseconds {
            let allLessons = try context.fetch(FetchDescriptor<StudentLesson>())
            let filtered = allLessons.filter { $0.studentIDs.contains(targetIDString) }
            _ = filtered.count
        }

        ms.printBenchmark(
            name: "StudentLesson In-Memory Filter",
            target: "< 300ms",
            baseline: "~200ms",
            additionalStats: [
                "Total lessons fetched, then filtered in-memory (studentIDs is @Transient)"
            ]
        )
        #expect(ms.elapsed < 1000, "StudentLesson In-Memory Filter exceeded 1000ms threshold")
    }

    // MARK: - 5. Batch Student Lookup

    @Test("Batch Student Lookup — dictionary-based participant resolution")
    func batchStudentLookupPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.workQueryTypes)
        let context = ModelContext(container)

        // Seed: 30 students, 200 work items with participants
        let students = TestDataBuilder.createStudents(count: 30, context: context)
        _ = try TestDataBuilder.createWorkItems(
            count: 200,
            context: context,
            students: students,
            includeParticipants: true
        )
        try context.save()

        // Measure: batch lookup pattern (fetch all students into dict, resolve per work item)
        let ms = try PerformanceMeasurement.measureMilliseconds {
            let allWork = try context.fetch(FetchDescriptor<WorkModel>())
            let allStudents = try context.fetch(FetchDescriptor<Student>())
            let studentDict = Dictionary(
                uniqueKeysWithValues: allStudents.map { ($0.id.uuidString, $0) }
            )

            var results: [UUID: [Student]] = [:]
            for work in allWork {
                let pIDs = (work.participants ?? []).map { $0.studentID }
                results[work.id] = pIDs.compactMap { studentDict[$0] }
            }
            _ = results.count
        }

        ms.printBenchmark(
            name: "Batch Student Lookup",
            target: "< 200ms",
            baseline: "~100ms"
        )
        #expect(ms.elapsed < 500, "Batch Student Lookup exceeded 500ms threshold")
    }

    // MARK: - 6. Note Scope Query

    @Test("Note Scope Query — searchIndexStudentID + scopeIsAll + NoteStudentLink")
    func noteScopeQueryPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.noteQueryTypes)
        let context = ModelContext(container)

        // Seed: 10 students, 500 notes with mixed scopes
        let students = TestDataBuilder.createStudents(count: 10, context: context)
        TestDataBuilder.createMixedScopeNotes(
            count: 500,
            students: students,
            context: context
        )
        try context.save()

        // Measure: dual-query pattern (mirrors NoteRepository.fetchNotesForStudent)
        let targetStudentID = students[0].id
        let targetStudentString = targetStudentID.uuidString

        let ms = try PerformanceMeasurement.measureMilliseconds {
            // Primary: notes directly scoped to this student or to all
            let directDescriptor = FetchDescriptor<Note>(
                predicate: #Predicate { note in
                    note.searchIndexStudentID == targetStudentID || note.scopeIsAll == true
                }
            )
            let directNotes = try context.fetch(directDescriptor)

            // Secondary: notes linked via NoteStudentLink (multi-student scope)
            let linkDescriptor = FetchDescriptor<NoteStudentLink>(
                predicate: #Predicate { link in
                    link.studentID == targetStudentString
                }
            )
            let links = try context.fetch(linkDescriptor)
            _ = directNotes.count + links.count
        }

        ms.printBenchmark(
            name: "Note Scope Query",
            target: "< 100ms",
            baseline: "~50ms"
        )
        #expect(ms.elapsed < 500, "Note Scope Query exceeded 500ms threshold")
    }

    // MARK: - 7. WorkCheckIn Scheduled Query

    @Test("WorkCheckIn Scheduled Query — statusRaw + date predicate, grouped by work")
    func workCheckInQueryPerformance() throws {
        let container = try makeTestContainer(for: BenchmarkContainers.checkInTypes)
        let context = ModelContext(container)

        // Seed: 30 students, 300 work items, each with 1-2 check-ins
        let students = TestDataBuilder.createStudents(count: 30, context: context)
        let workItems = try TestDataBuilder.createWorkItems(
            count: 300,
            context: context,
            students: students,
            includeParticipants: false
        )

        // Create check-ins: ~600 total, mix of scheduled/completed
        let today = AppCalendar.startOfDay(Date())
        for (i, work) in workItems.enumerated() {
            let checkIn1 = WorkCheckIn(
                workID: work.id,
                date: today.addingTimeInterval(Double(i % 14 - 7) * 86400),
                status: (i % 3 == 0) ? .completed : .scheduled,
                work: work
            )
            context.insert(checkIn1)

            if i % 2 == 0 {
                let checkIn2 = WorkCheckIn(
                    workID: work.id,
                    date: today.addingTimeInterval(Double(i % 21 - 10) * 86400),
                    status: .scheduled,
                    work: work
                )
                context.insert(checkIn2)
            }
        }
        try context.save()

        // Measure: fetch scheduled check-ins up to tomorrow, group by work
        let scheduledRaw = WorkCheckInStatus.scheduled.rawValue
        let tomorrow = today.addingTimeInterval(86400)

        let ms = try PerformanceMeasurement.measureMilliseconds {
            let descriptor = FetchDescriptor<WorkCheckIn>(
                predicate: #Predicate { ci in
                    ci.statusRaw == scheduledRaw && ci.date <= tomorrow
                }
            )
            let checkIns = try context.fetch(descriptor)

            var byWork: [String: [WorkCheckIn]] = [:]
            for ci in checkIns {
                byWork[ci.workID, default: []].append(ci)
            }
            _ = checkIns.count + byWork.count
        }

        ms.printBenchmark(
            name: "WorkCheckIn Scheduled Query",
            target: "< 100ms",
            baseline: "~40ms"
        )
        #expect(ms.elapsed < 500, "WorkCheckIn Scheduled Query exceeded 500ms threshold")
    }
}

#endif
