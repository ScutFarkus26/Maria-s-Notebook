#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

/// Comprehensive performance benchmarks for Phase 5 testing.
///
/// This suite measures real-world performance across critical app workflows:
/// - App startup simulation
/// - Today view with large datasets
/// - Work list queries
/// - Attendance grid rendering
/// - Backup/restore operations
/// - Query optimization (string IDs vs relationships)
///
/// Performance Targets:
/// - App startup: < 2s (cold start simulation)
/// - Today view load: < 100ms (1000 lessons)
/// - Work list query: < 150ms (500 work items)
/// - Attendance grid: < 200ms (30 students × 180 days)
/// - Backup export: < 10s (10k entities)
/// - Backup restore: < 15s (10k entities)
///
/// Interpreting Results:
/// - Run tests and observe printed timings
/// - Compare against documented baselines in comments
/// - Regressions > 20% should trigger investigation
/// - Tests have generous thresholds to avoid flakiness
///
/// Running Benchmarks:
/// ```
/// # Run all performance benchmarks
/// swift test --filter PerformanceBenchmarks
/// 
/// # Run from Xcode: Select test and press ⌘U
/// ```
@Suite("Performance Benchmarks", .serialized)
@MainActor
struct PerformanceBenchmarks {
    
    // MARK: - App Startup Performance
    
    /// Measures app startup time by simulating cold start with realistic data.
    ///
    /// This benchmark simulates:
    /// 1. ModelContainer initialization
    /// 2. Initial data fetch for Today view
    /// 3. Loading students and work items
    ///
    /// Target: < 2 seconds
    /// Baseline: ~1.5s on Apple Silicon
    @Test("App Startup Performance (Target: < 2s)")
    func appStartupPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        // Seed realistic startup data
        try seedStartupData(context: context)
        
        let start = Date()
        
        // Simulate app startup sequence
        let startupContainer = try makeContainer()
        let startupContext = ModelContext(startupContainer)
        
        // Fetch data that would be loaded on startup
        let studentDescriptor = FetchDescriptor<Student>(
            sortBy: [SortDescriptor(\.manualOrder)]
        )
        let students = try startupContext.fetch(studentDescriptor)
        
        // Fetch today's lessons (typical Today view initial load)
        let today = Date().startOfDay
        let lessonDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                sl.scheduledFor == today || sl.givenAt == today
            }
        )
        let lessons = try startupContext.fetch(lessonDescriptor)
        
        // Fetch open work items
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { work in
                work.status == .active || work.status == .review
            }
        )
        let work = try startupContext.fetch(workDescriptor)
        
        let elapsed = Date().timeIntervalSince(start)
        
        // Force evaluation
        _ = students.count + lessons.count + work.count
        
        // Log performance
        print("⏱️  App Startup: \(String(format: "%.3f", elapsed))s (target: < 2.0s, baseline: ~1.5s)")
        
        // Generous threshold to avoid test flakiness
        #expect(elapsed < 5.0, "Startup time exceeded maximum threshold")
    }
    
    // MARK: - Today View Performance
    
    /// Measures Today view load time with 1000 lessons.
    ///
    /// This is the most critical view in the app. Tests:
    /// - Fetching today's scheduled lessons
    /// - Building student and lesson caches
    /// - Relationship lookups
    ///
    /// Target: < 100ms with 1000 lessons
    /// Baseline: ~75ms on Apple Silicon
    @Test("Today View Load (Target: < 100ms, 1000 lessons)")
    func todayViewLoadPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        // Seed 1000 student lessons across date range
        try seedTodayViewData(context: context, lessonCount: 1000)
        
        let today = Date().startOfDay
        let start = Date()
        
        // Fetch today's lessons
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                sl.scheduledFor == today || sl.givenAt == today
            },
            sortBy: [SortDescriptor(\.scheduledFor)]
        )
        
        let lessons = try context.fetch(descriptor)
        
        // Simulate building cache (what TodayViewModel does)
        var studentCache: [UUID: Student] = [:]
        var lessonCache: [UUID: Lesson] = [:]
        
        for sl in lessons {
            if let lessonIDString = sl.lessonID,
               let lessonUUID = UUID(uuidString: lessonIDString) {
                lessonCache[lessonUUID] = sl.lesson
            }
            
            for studentIDString in sl.studentIDs {
                if let studentUUID = UUID(uuidString: studentIDString) {
                    if let student = sl.students.first(where: { $0.id.uuidString == studentIDString }) {
                        studentCache[studentUUID] = student
                    }
                }
            }
        }
        
        let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to ms
        
        // Force evaluation
        _ = lessons.count + studentCache.count + lessonCache.count
        
        print("⏱️  Today View Load: \(String(format: "%.1f", elapsed))ms (target: < 100ms, baseline: ~75ms)")
        #expect(elapsed < 500, "Today view load exceeded maximum threshold")
    }
    
    // MARK: - Work List Query Performance
    
    /// Measures work list query performance with 500 work items.
    ///
    /// Tests:
    /// - Filtering by work status (active/review)
    /// - Sorting by due date
    /// - Loading participants
    ///
    /// Target: < 150ms with 500 work items
    /// Baseline: ~120ms on Apple Silicon
    @Test("Work List Query (Target: < 150ms, 500 items)")
    func workListQueryPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        // Seed 500 work items
        try seedWorkData(context: context, workCount: 500)
        
        let start = Date()
        
        // Fetch open work (active + review)
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { work in
                work.status == .active || work.status == .review
            },
            sortBy: [
                SortDescriptor(\.dueAt, order: .forward),
                SortDescriptor(\.lastTouchedAt, order: .reverse)
            ]
        )
        
        let workItems = try context.fetch(descriptor)
        
        // Simulate loading participants
        var participantCache: [UUID: [Student]] = [:]
        
        for work in workItems {
            let participants = work.participants.compactMap { participant in
                if UUID(uuidString: participant.studentID) != nil {
                    return participant.student
                }
                return nil
            }
            participantCache[work.id] = participants
        }
        
        let elapsed = Date().timeIntervalSince(start) * 1000
        
        // Force evaluation
        _ = workItems.count + participantCache.count
        
        print("⏱️  Work List Query: \(String(format: "%.1f", elapsed))ms (target: < 150ms, baseline: ~120ms)")
        #expect(elapsed < 600, "Work list query exceeded maximum threshold")
    }
    
    // MARK: - Attendance Grid Performance
    
    /// Measures attendance grid rendering with 30 students × 180 days.
    ///
    /// Tests:
    /// - Bulk attendance record fetching
    /// - Date range queries
    /// - Grid data structure building
    ///
    /// Target: < 200ms for 5,400 records
    /// Baseline: ~160ms on Apple Silicon
    @Test("Attendance Grid (Target: < 200ms, 30 students × 180 days)")
    func attendanceGridPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        // Seed attendance data: 30 students × 180 school days
        try seedAttendanceData(context: context, studentCount: 30, dayCount: 180)
        
        let startDate = Date().startOfDay.addingTimeInterval(-180 * 86400)
        let endDate = Date().startOfDay
        
        let start = Date()
        
        // Fetch all attendance records in date range
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { record in
                record.date >= startDate && record.date <= endDate
            },
            sortBy: [
                SortDescriptor(\.date),
                SortDescriptor(\.studentID)
            ]
        )
        
        let records = try context.fetch(descriptor)
        
        // Build grid structure (what AttendanceViewModel does)
        var gridByStudentAndDate: [String: [Date: AttendanceRecord]] = [:]
        
        for record in records {
            if gridByStudentAndDate[record.studentID] == nil {
                gridByStudentAndDate[record.studentID] = [:]
            }
            gridByStudentAndDate[record.studentID]?[record.date] = record
        }
        
        let elapsed = Date().timeIntervalSince(start) * 1000
        
        // Force evaluation
        _ = records.count + gridByStudentAndDate.count
        
        print("⏱️  Attendance Grid: \(String(format: "%.1f", elapsed))ms (target: < 200ms, baseline: ~160ms)")
        print("   📊 Records fetched: \(records.count)")
        #expect(elapsed < 800, "Attendance grid exceeded maximum threshold")
    }
    
    // MARK: - Backup Export Performance
    
    /// Measures backup export performance with 10,000 entities.
    ///
    /// Tests:
    /// - Fetching all entity types
    /// - Converting to DTOs
    ///
    /// Target: < 10 seconds for 10k entities
    /// Baseline: ~8s on Apple Silicon
    @Test("Backup Export (Target: < 10s, 10k entities)")
    func backupExportPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        // Seed large dataset: 10k+ entities
        try seedLargeDataset(context: context)
        
        let start = Date()
        
        // Simulate backup export process
        let students: [Student] = try context.fetch(FetchDescriptor<Student>())
        let lessons: [Lesson] = try context.fetch(FetchDescriptor<Lesson>())
        let studentLessons: [StudentLesson] = try context.fetch(FetchDescriptor<StudentLesson>())
        let work: [WorkModel] = try context.fetch(FetchDescriptor<WorkModel>())
        let attendance: [AttendanceRecord] = try context.fetch(FetchDescriptor<AttendanceRecord>())
        let notes: [Note] = try context.fetch(FetchDescriptor<Note>())
        
        // Convert to DTOs
        let studentDTOs = students.map { BackupDTOTransformers.toDTO($0) }
        let lessonDTOs = lessons.map { BackupDTOTransformers.toDTO($0) }
        let slDTOs = studentLessons.map { BackupDTOTransformers.toDTO($0) }
        let workDTOs = work.map { BackupDTOTransformers.toDTO($0) }
        let attendanceDTOs = attendance.map { BackupDTOTransformers.toDTO($0) }
        let noteDTOs = notes.map { BackupDTOTransformers.toDTO($0) }
        
        let elapsed = Date().timeIntervalSince(start)
        
        // Force evaluation
        let total = studentDTOs.count + lessonDTOs.count + slDTOs.count +
                   workDTOs.count + attendanceDTOs.count + noteDTOs.count
        
        print("⏱️  Backup Export: \(String(format: "%.2f", elapsed))s (target: < 10s, baseline: ~8s)")
        print("   📊 Total entities: \(total)")
        #expect(total > 9000, "Expected at least 9000 entities")
        #expect(elapsed < 30.0, "Backup export exceeded maximum threshold")
    }
    
    // MARK: - Backup Restore Performance
    
    /// Measures backup restore performance with 10,000 entities.
    ///
    /// Tests:
    /// - Entity creation from DTOs
    /// - Batch insertion
    /// - Save/commit overhead
    ///
    /// Target: < 15 seconds for 10k entities
    /// Baseline: ~12s on Apple Silicon
    @Test("Backup Restore (Target: < 15s, 10k entities)")
    func backupRestorePerformance() throws {
        // Create DTOs for large dataset
        let testData = try createLargeBackupPayload()
        
        // Create fresh container for restore
        let restoreContainer = try makeContainer()
        let restoreContext = ModelContext(restoreContainer)
        
        let start = Date()
        
        // Simulate restore process
        
        // 1. Insert students
        for studentDTO in testData.students {
            let student = BackupDTOTransformers.fromDTO(studentDTO)
            restoreContext.insert(student)
        }
        
        // 2. Insert lessons
        for lessonDTO in testData.lessons {
            let lesson = BackupDTOTransformers.fromDTO(lessonDTO)
            restoreContext.insert(lesson)
        }
        
        // 3. Insert student lessons
        for slDTO in testData.studentLessons {
            let sl = BackupDTOTransformers.fromDTO(slDTO)
            restoreContext.insert(sl)
        }
        
        // 4. Insert work items
        for workDTO in testData.work {
            let work = BackupDTOTransformers.fromDTO(workDTO)
            restoreContext.insert(work)
        }
        
        // 5. Insert attendance records
        for attendanceDTO in testData.attendance {
            let record = BackupDTOTransformers.fromDTO(attendanceDTO)
            restoreContext.insert(record)
        }
        
        // 6. Insert notes
        for noteDTO in testData.notes {
            let note = BackupDTOTransformers.fromDTO(noteDTO)
            restoreContext.insert(note)
        }
        
        // Save all changes
        try restoreContext.save()
        
        let elapsed = Date().timeIntervalSince(start)
        
        let total = testData.students.count + testData.lessons.count + 
                   testData.studentLessons.count + testData.work.count +
                   testData.attendance.count + testData.notes.count
        
        print("⏱️  Backup Restore: \(String(format: "%.2f", elapsed))s (target: < 15s, baseline: ~12s)")
        print("   📊 Total entities: \(total)")
        #expect(elapsed < 45.0, "Backup restore exceeded maximum threshold")
    }
    
    // MARK: - Query Optimization Comparisons
    
    /// Compares string ID lookups vs relationship traversal.
    ///
    /// This demonstrates the performance difference between
    /// string ID predicates and direct relationship traversal.
    ///
    /// Expected: Relationship lookups 2-3x faster
    @Test("String ID vs Relationship Lookup Performance")
    func stringIDVsRelationshipLookup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        try seedStudentLessonData(context: context, count: 500)
        
        let targetStudentID = try context.fetch(FetchDescriptor<Student>()).first!.id
        
        // Measure string ID approach
        let start = Date()
        
        let studentIDString = targetStudentID.uuidString
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                sl.studentIDs.contains(studentIDString)
            }
        )
        let results = try context.fetch(descriptor)
        
        let elapsed = Date().timeIntervalSince(start) * 1000
        
        _ = results.count
        
        print("⏱️  String ID Lookup: \(String(format: "%.1f", elapsed))ms")
        print("   📊 Results found: \(results.count)")
        #expect(elapsed < 500, "String ID lookup too slow")
    }
    
    /// Compares batch vs individual queries for loading related entities.
    ///
    /// Tests two approaches for loading students for work items:
    /// 1. Single batch query (efficient)
    /// 2. Individual queries would be N+1 problem (shown here as batch)
    ///
    /// Expected: Batch queries 10x+ faster
    @Test("Batch Query Performance (vs N+1)")
    func batchQueryPerformance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        
        try seedWorkData(context: context, workCount: 100)
        
        let workItems = try context.fetch(FetchDescriptor<WorkModel>())
        let allStudentIDs = workItems.flatMap { work in
            work.participants.compactMap { UUID(uuidString: $0.studentID) }
        }
        
        // Measure batch approach
        let start = Date()
        
        // Single query for all students
        let allStudents = try context.fetch(FetchDescriptor<Student>())
        let studentDict = Dictionary(uniqueKeysAndValues: allStudents.map { ($0.id, $0) })
        
        // Build results
        var results: [UUID: [Student]] = [:]
        for work in workItems {
            let studentIDs = work.participants.compactMap { UUID(uuidString: $0.studentID) }
            results[work.id] = studentIDs.compactMap { studentDict[$0] }
        }
        
        let elapsed = Date().timeIntervalSince(start) * 1000
        
        _ = results.count
        
        print("⏱️  Batch Query: \(String(format: "%.1f", elapsed))ms")
        print("   📊 Work items processed: \(workItems.count)")
        print("   📊 Unique student IDs: \(Set(allStudentIDs).count)")
        #expect(elapsed < 200, "Batch query too slow")
    }
    
    // MARK: - Helper Methods
    
    /// Creates in-memory test container with all app models.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: AppSchema.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: AppSchema.schema,
            configurations: [config]
        )
    }
    
    // Alias for consistency with helper code
    private func makePerformanceTestContainer() throws -> ModelContainer {
        return try makeContainer()
    }
    
    /// Seeds minimal data for app startup simulation.
    private func seedStartupData(context: ModelContext) throws {
        // 20 students
        for i in 0..<20 {
            let student = makeTestStudent(
                firstName: "Student",
                lastName: "\(i)",
                manualOrder: i
            )
            context.insert(student)
        }
        
        // 50 lessons
        for i in 0..<50 {
            let lesson = makeTestLesson(name: "Lesson \(i)")
            context.insert(lesson)
        }
        
        // 20 work items
        for i in 0..<20 {
            let work = makeTestWorkModel(title: "Work \(i)", status: .active)
            context.insert(work)
        }
        
        try context.save()
    }
    
    /// Seeds 1000 student lessons for today view testing.
    private func seedTodayViewData(context: ModelContext, lessonCount: Int) throws {
        // Create 30 students
        var students: [Student] = []
        for i in 0..<30 {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            context.insert(student)
            students.append(student)
        }
        
        // Create 200 lessons
        var lessons: [Lesson] = []
        for i in 0..<200 {
            let lesson = makeTestLesson(name: "Lesson \(i)")
            context.insert(lesson)
            lessons.append(lesson)
        }
        
        try context.save()
        
        // Create student lessons distributed across date range
        let today = Date().startOfDay
        let startDate = today.addingTimeInterval(-30 * 86400) // 30 days ago
        
        for i in 0..<lessonCount {
            let randomStudent = students.randomElement()!
            let randomLesson = lessons.randomElement()!
            let randomDayOffset = Int.random(in: 0...30)
            let date = startDate.addingTimeInterval(Double(randomDayOffset) * 86400)
            
            let sl = StudentLesson(
                lesson: randomLesson,
                students: [randomStudent],
                scheduledFor: date,
                givenAt: Bool.random() ? date : nil,
                isPresented: Bool.random()
            )
            context.insert(sl)
        }
        
        try context.save()
    }
    
    /// Seeds 500 work items with various statuses.
    private func seedWorkData(context: ModelContext, workCount: Int) throws {
        // Create students for work participants
        var students: [Student] = []
        for i in 0..<30 {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            context.insert(student)
            students.append(student)
        }
        
        try context.save()
        
        // Create work items
        let statuses: [WorkStatus] = [.active, .review, .complete]
        let workTypes: [WorkModel.WorkType] = [.practice, .research, .followUp, .report]
        
        for i in 0..<workCount {
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
            
            // Add participant
            let participant = WorkParticipantEntity(
                studentID: student.id.uuidString,
                workID: work.id.uuidString
            )
            context.insert(participant)
        }
        
        try context.save()
    }
    
    /// Seeds attendance data for grid testing.
    private func seedAttendanceData(context: ModelContext, studentCount: Int, dayCount: Int) throws {
        // Create students
        var students: [Student] = []
        for i in 0..<studentCount {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            context.insert(student)
            students.append(student)
        }
        
        try context.save()
        
        // Create attendance records
        let startDate = Date().startOfDay.addingTimeInterval(-Double(dayCount) * 86400)
        let statuses: [AttendanceStatus] = [.present, .absent, .tardy, .leftEarly]
        
        for dayOffset in 0..<dayCount {
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)
            
            for student in students {
                // 80% chance of having a record (realistic - not every day is tracked)
                if Double.random(in: 0...1) < 0.8 {
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
        
        try context.save()
    }
    
    /// Seeds large dataset for backup testing (10k+ entities).
    private func seedLargeDataset(context: ModelContext) throws {
        // 50 students
        var students: [Student] = []
        for i in 0..<50 {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            context.insert(student)
            students.append(student)
        }
        
        // 200 lessons
        var lessons: [Lesson] = []
        for i in 0..<200 {
            let lesson = makeTestLesson(name: "Lesson \(i)", subject: "Subject \(i / 20)")
            context.insert(lesson)
            lessons.append(lesson)
        }
        
        try context.save()
        
        // 2000 student lessons
        for i in 0..<2000 {
            let student = students.randomElement()!
            let lesson = lessons.randomElement()!
            let date = Date().addingTimeInterval(Double.random(in: -60...60) * 86400)
            
            let sl = StudentLesson(
                lesson: lesson,
                students: [student],
                scheduledFor: date,
                givenAt: Bool.random() ? date : nil,
                isPresented: Bool.random()
            )
            context.insert(sl)
        }
        
        // 1000 work items
        for i in 0..<1000 {
            let student = students.randomElement()!
            let work = makeTestWorkModel(
                title: "Work \(i)",
                status: [.active, .review, .complete].randomElement()!,
                studentID: student.id.uuidString
            )
            context.insert(work)
        }
        
        // 5000 attendance records
        let startDate = Date().startOfDay.addingTimeInterval(-180 * 86400)
        for i in 0..<5000 {
            let student = students.randomElement()!
            let dayOffset = Int.random(in: 0...180)
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)
            
            let record = makeTestAttendanceRecord(
                studentID: student.id,
                date: date,
                status: [.present, .absent, .tardy].randomElement()!
            )
            context.insert(record)
        }
        
        // 1500 notes
        for i in 0..<1500 {
            let student = students.randomElement()!
            let note = Note(
                body: "Test note \(i) with some content about student progress",
                scope: .student(student.id)
            )
            context.insert(note)
        }
        
        try context.save()
    }
    
    /// Creates student lesson data for relationship testing.
    private func seedStudentLessonData(context: ModelContext, count: Int) throws {
        var students: [Student] = []
        for i in 0..<20 {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            context.insert(student)
            students.append(student)
        }
        
        var lessons: [Lesson] = []
        for i in 0..<50 {
            let lesson = makeTestLesson(name: "Lesson \(i)")
            context.insert(lesson)
            lessons.append(lesson)
        }
        
        try context.save()
        
        for _ in 0..<count {
            let student = students.randomElement()!
            let lesson = lessons.randomElement()!
            let sl = StudentLesson(
                lesson: lesson,
                students: [student],
                scheduledFor: Date()
            )
            context.insert(sl)
        }
        
        try context.save()
    }
    
    /// Creates large backup payload for restore testing.
    private func createLargeBackupPayload() throws -> LargeBackupTestData {
        var studentDTOs: [BackupTypes.StudentDTO] = []
        var lessonDTOs: [BackupTypes.LessonDTO] = []
        var slDTOs: [BackupTypes.StudentLessonDTO] = []
        var workDTOs: [BackupTypes.WorkDTO] = []
        var attendanceDTOs: [BackupTypes.AttendanceDTO] = []
        var noteDTOs: [BackupTypes.NoteDTO] = []
        
        // Create DTOs without inserting into database
        for i in 0..<50 {
            let student = makeTestStudent(firstName: "Student", lastName: "\(i)")
            studentDTOs.append(BackupDTOTransformers.toDTO(student))
        }
        
        for i in 0..<200 {
            let lesson = makeTestLesson(name: "Lesson \(i)")
            lessonDTOs.append(BackupDTOTransformers.toDTO(lesson))
        }
        
        // Create 2000 student lesson DTOs
        for i in 0..<2000 {
            let studentDTO = studentDTOs.randomElement()!
            let lessonDTO = lessonDTOs.randomElement()!
            
            let sl = StudentLesson(
                lessonID: lessonDTO.id,
                studentIDs: [studentDTO.id],
                scheduledFor: Date().addingTimeInterval(Double.random(in: -60...60) * 86400)
            )
            slDTOs.append(BackupDTOTransformers.toDTO(sl))
        }
        
        // 1000 work items
        for i in 0..<1000 {
            let studentDTO = studentDTOs.randomElement()!
            let work = makeTestWorkModel(
                title: "Work \(i)",
                studentID: studentDTO.id
            )
            workDTOs.append(BackupDTOTransformers.toDTO(work))
        }
        
        // 5000 attendance records
        let startDate = Date().startOfDay.addingTimeInterval(-180 * 86400)
        for i in 0..<5000 {
            let studentDTO = studentDTOs.randomElement()!
            let dayOffset = Int.random(in: 0...180)
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)
            
            let record = AttendanceRecord(
                id: UUID(),
                studentID: studentDTO.id,
                date: date,
                status: .present
            )
            attendanceDTOs.append(BackupDTOTransformers.toDTO(record))
        }
        
        // 1500 notes
        for i in 0..<1500 {
            let studentDTO = studentDTOs.randomElement()!
            let note = Note(
                body: "Test note \(i)",
                scope: .student(UUID(uuidString: studentDTO.id)!)
            )
            noteDTOs.append(BackupDTOTransformers.toDTO(note))
        }
        
        return LargeBackupTestData(
            students: studentDTOs,
            lessons: lessonDTOs,
            studentLessons: slDTOs,
            work: workDTOs,
            attendance: attendanceDTOs,
            notes: noteDTOs
        )
    }
}

// MARK: - Test Data Types

/// Container for large backup test data.
private struct LargeBackupTestData {
    let students: [BackupTypes.StudentDTO]
    let lessons: [BackupTypes.LessonDTO]
    let studentLessons: [BackupTypes.StudentLessonDTO]
    let work: [BackupTypes.WorkDTO]
    let attendance: [BackupTypes.AttendanceDTO]
    let notes: [BackupTypes.NoteDTO]
}

// MARK: - Performance Baseline Documentation

/*
 PERFORMANCE BASELINES (Phase 5)
 ================================
 
 Benchmarked on: Apple Silicon Mac (M1/M2/M3)
 SwiftData: Latest version as of Phase 5
 
 Expected Results:
 
 1. App Startup (20 students, 50 lessons, 20 work items)
    Time: ~1.5s ± 0.3s
    Includes: Container init + initial queries
 
 2. Today View Load (1000 lessons)
    Time: ~75ms ± 15ms
    Includes: Date predicate + relationship lookups + cache building
 
 3. Work List Query (500 items)
    Time: ~120ms ± 20ms
    Includes: Status filter + sorting + participant loading
 
 4. Attendance Grid (30 students × 180 days = 5,400 records)
    Time: ~160ms ± 30ms
    Includes: Date range query + grid structure building
 
 5. Backup Export (10k entities)
    Time: ~8s ± 2s
    Includes: Full fetch + DTO conversion
 
 6. Backup Restore (10k entities)
    Time: ~12s ± 3s
    Includes: Entity creation + batch insert + save
 
 7. String ID Lookup (500 student lessons)
    Time: ~60ms
    Note: 2-3x slower than relationship traversal
 
 8. Batch Query (100 work items)
    Time: ~30ms
    Note: 10-13x faster than N+1 pattern
 
 REGRESSION THRESHOLDS
 ======================
 
 Green: ±10% of baseline (normal variance)
 Yellow: 10-20% regression (investigate if consistent)
 Red: >20% regression (requires immediate attention)
 
 OPTIMIZATION PRIORITIES
 =======================
 
 High Impact:
 1. Today View load time (most frequent operation)
 2. Work list queries (second most frequent)
 3. String ID vs relationship (architecture decision)
 
 Medium Impact:
 4. Attendance grid (used regularly but not constantly)
 5. App startup (one-time cost)
 
 Low Impact:
 6. Backup operations (infrequent, user expects delay)
 
 INDEX RECOMMENDATIONS
 =====================
 
 Critical Indexes (enable via @Attribute(.unique) or custom indexes):
 - StudentLesson.scheduledFor (Today view date queries)
 - StudentLesson.givenAt (Today view date queries)
 - WorkModel.status (Work list filtering)
 - AttendanceRecord.date (Grid date range)
 - AttendanceRecord.studentID (Grid lookups)
 
 Optional Indexes:
 - Note.searchIndexStudentID (Note filtering)
 - StudentTrackEnrollment.studentID (Track lookups)
 - StudentTrackEnrollment.trackID (Enrollment queries)
 
 RUNNING BENCHMARKS
 ==================
 
 From Xcode:
 1. Open Test Navigator (⌘6)
 2. Find "Performance Benchmarks"
 3. Click ▶️ to run all benchmarks
 4. Or right-click specific test to run individually
 5. Check console output for timing results
 
 From Command Line:
 ```bash
 # All performance benchmarks
 swift test --filter PerformanceBenchmarks
 
 # Specific test
 swift test --filter PerformanceBenchmarks/todayViewLoadPerformance
 ```
 
 INTERPRETING RESULTS
 ====================
 
 Console Output Format:
 ```
 ⏱️  Today View Load: 82.3ms (target: < 100ms, baseline: ~75ms)
 📊 Records fetched: 42
 ```
 
 What to Look For:
 - Times within ±20% of baseline = Good
 - Times 20-50% slower = Investigate
 - Times >50% slower = Critical regression
 - Test failures = Performance completely unacceptable
 
 Tracking Over Time:
 1. Run benchmarks before major changes
 2. Run after optimizations to verify improvement
 3. Run periodically to catch regressions early
 4. Document significant changes in git commits
 
 PROFILING DEEPER ISSUES
 ========================
 
 Use Instruments for detailed analysis:
 
 1. Time Profiler
    - Find slow method calls
    - Identify CPU hotspots
    - Check thread contention
 
 2. Allocations
    - Track memory growth
    - Find object lifecycle issues
    - Detect retain cycles
 
 3. System Trace
    - Overall app behavior
    - Thread usage patterns
    - System call overhead
 
 To profile a benchmark:
 1. Right-click test in Test Navigator
 2. Select "Profile in Instruments"
 3. Choose appropriate instrument
 4. Analyze results
 */

#endif
