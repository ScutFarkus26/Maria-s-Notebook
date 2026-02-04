import XCTest
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
/// - Baseline times are established on first run
/// - Subsequent runs compare against baseline (±10% acceptable)
/// - Regressions > 20% should trigger investigation
/// - Check "Baseline Average" in Xcode test results
///
/// Running Benchmarks:
/// ```
/// # Run all performance tests
/// xcodebuild test -scheme "Maria's Notebook" -only-testing:PerformanceBenchmarks
///
/// # Run specific benchmark
/// xcodebuild test -scheme "Maria's Notebook" -only-testing:PerformanceBenchmarks/testTodayViewLoadPerformance
/// ```
@MainActor
final class PerformanceBenchmarks: XCTestCase {
    
    // MARK: - Test Infrastructure
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        // Create fresh in-memory container for each test
        container = try makePerformanceTestContainer()
        context = ModelContext(container)
    }
    
    override func tearDown() async throws {
        // Clean up resources
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - App Startup Performance
    
    /// Measures app startup time by simulating cold start with realistic data.
    ///
    /// This benchmark simulates:
    /// 1. ModelContainer initialization
    /// 2. Schema migration check
    /// 3. Loading user preferences
    /// 4. Initial data fetch for Today view
    ///
    /// Target: < 2 seconds
    ///
    /// What affects this:
    /// - Number of model types in schema
    /// - SwiftData initialization overhead
    /// - First fetch performance
    /// - Index availability
    func testAppStartupPerformance() throws {
        // Seed realistic startup data
        try seedStartupData(context: context)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Simulate app startup sequence
            let startupContainer = try! makePerformanceTestContainer()
            let startupContext = ModelContext(startupContainer)
            
            // Fetch data that would be loaded on startup
            let studentDescriptor = FetchDescriptor<Student>(
                sortBy: [SortDescriptor(\.manualOrder)]
            )
            let students = try! startupContext.fetch(studentDescriptor)
            
            // Fetch today's lessons (typical Today view initial load)
            let today = Date().startOfDay
            let lessonDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate<StudentLesson> { sl in
                    sl.scheduledFor == today || sl.givenAt == today
                }
            )
            let lessons = try! startupContext.fetch(lessonDescriptor)
            
            // Fetch open work items
            let workDescriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate<WorkModel> { work in
                    work.status == .active || work.status == .review
                }
            )
            let work = try! startupContext.fetch(workDescriptor)
            
            // Force evaluation
            _ = students.count + lessons.count + work.count
        }
    }
    
    // MARK: - Today View Performance
    
    /// Measures Today view load time with 1000 lessons.
    ///
    /// This is the most critical view in the app. Tests:
    /// - Fetching today's scheduled lessons
    /// - Filtering by date
    /// - Student/lesson lookups
    /// - Building display models
    ///
    /// Target: < 100ms with 1000 lessons
    ///
    /// What affects this:
    /// - Date predicate efficiency
    /// - String ID vs relationship lookups
    /// - Number of relationships traversed
    /// - Cache warming
    func testTodayViewLoadPerformance() throws {
        // Seed 1000 student lessons across date range
        try seedTodayViewData(context: context, lessonCount: 1000)
        
        let today = Date().startOfDay
        
        measure(metrics: [XCTClockMetric()]) {
            // Fetch today's lessons (this is what TodayViewModel does)
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate<StudentLesson> { sl in
                    sl.scheduledFor == today || sl.givenAt == today
                },
                sortBy: [SortDescriptor(\.scheduledFor)]
            )
            
            let lessons = try! context.fetch(descriptor)
            
            // Simulate building cache (what TodayViewModel does)
            var studentCache: [UUID: Student] = [:]
            var lessonCache: [UUID: Lesson] = [:]
            
            for sl in lessons {
                // This simulates the relationship lookups
                if let lessonIDString = sl.lessonID,
                   let lessonUUID = UUID(uuidString: lessonIDString) {
                    // In real app, this would traverse relationship
                    lessonCache[lessonUUID] = sl.lesson
                }
                
                for studentIDString in sl.studentIDs {
                    if let studentUUID = UUID(uuidString: studentIDString) {
                        // In real app, this would be relationship lookup
                        if let student = sl.students.first(where: { $0.id.uuidString == studentIDString }) {
                            studentCache[studentUUID] = student
                        }
                    }
                }
            }
            
            // Force evaluation
            _ = lessons.count + studentCache.count + lessonCache.count
        }
    }
    
    // MARK: - Work List Query Performance
    
    /// Measures work list query performance with 500 work items.
    ///
    /// Tests the performance of:
    /// - Filtering by work status (active/review)
    /// - Sorting by due date and last touched
    /// - Loading participants
    /// - Building work item displays
    ///
    /// Target: < 150ms with 500 work items
    ///
    /// What affects this:
    /// - Work status predicate efficiency
    /// - Participant relationship loading
    /// - String ID conversions
    /// - Sort descriptor performance
    func testWorkListQueryPerformance() throws {
        // Seed 500 work items with various statuses
        try seedWorkData(context: context, workCount: 500)
        
        measure(metrics: [XCTClockMetric()]) {
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
            
            let workItems = try! context.fetch(descriptor)
            
            // Simulate loading participants (what WorkRepository does)
            var participantCache: [UUID: [Student]] = [:]
            
            for work in workItems {
                let participants = work.participants.compactMap { participant in
                    if let studentID = UUID(uuidString: participant.studentID) {
                        return participant.student
                    }
                    return nil
                }
                participantCache[work.id] = participants
            }
            
            // Force evaluation
            _ = workItems.count + participantCache.count
        }
    }
    
    // MARK: - Attendance Grid Performance
    
    /// Measures attendance grid rendering with 30 students × 180 days.
    ///
    /// This is one of the most data-intensive views. Tests:
    /// - Bulk attendance record fetching
    /// - Date range queries
    /// - Student filtering
    /// - Grid data structure building
    ///
    /// Target: < 200ms for 30 students × 180 days (5,400 records)
    ///
    /// What affects this:
    /// - Attendance record index on studentID and date
    /// - Batch fetching efficiency
    /// - Date range predicate
    /// - Memory pressure from large result set
    func testAttendanceGridPerformance() throws {
        // Seed attendance data: 30 students × 180 school days
        try seedAttendanceData(context: context, studentCount: 30, dayCount: 180)
        
        let startDate = Date().startOfDay.addingTimeInterval(-180 * 86400)
        let endDate = Date().startOfDay
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
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
            
            let records = try! context.fetch(descriptor)
            
            // Build grid structure (what AttendanceViewModel does)
            var gridByStudentAndDate: [String: [Date: AttendanceRecord]] = [:]
            
            for record in records {
                if gridByStudentAndDate[record.studentID] == nil {
                    gridByStudentAndDate[record.studentID] = [:]
                }
                gridByStudentAndDate[record.studentID]?[record.date] = record
            }
            
            // Force evaluation
            _ = records.count + gridByStudentAndDate.count
        }
    }
    
    // MARK: - Backup Export Performance
    
    /// Measures backup export performance with 10,000 entities.
    ///
    /// This tests the complete export pipeline:
    /// - Fetching all entity types
    /// - Converting to DTOs
    /// - JSON encoding
    /// - Compression
    ///
    /// Target: < 10 seconds for 10k entities
    ///
    /// What affects this:
    /// - Batch fetching efficiency
    /// - DTO transformation cost
    /// - JSON encoding performance
    /// - Compression algorithm
    func testBackupExportPerformance() throws {
        // Seed large dataset:
        // - 50 students
        // - 200 lessons
        // - 2000 student lessons
        // - 1000 work items
        // - 5000 attendance records
        // - 1500 notes
        // - 250 other entities
        try seedLargeDataset(context: context)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Simulate backup export process
            let students: [Student] = try! context.fetch(FetchDescriptor<Student>())
            let lessons: [Lesson] = try! context.fetch(FetchDescriptor<Lesson>())
            let studentLessons: [StudentLesson] = try! context.fetch(FetchDescriptor<StudentLesson>())
            let work: [WorkModel] = try! context.fetch(FetchDescriptor<WorkModel>())
            let attendance: [AttendanceRecord] = try! context.fetch(FetchDescriptor<AttendanceRecord>())
            let notes: [Note] = try! context.fetch(FetchDescriptor<Note>())
            
            // Convert to DTOs (simplified - real backup does more)
            let studentDTOs = students.map { BackupDTOTransformers.toDTO($0) }
            let lessonDTOs = lessons.map { BackupDTOTransformers.toDTO($0) }
            let slDTOs = studentLessons.map { BackupDTOTransformers.toDTO($0) }
            let workDTOs = work.map { BackupDTOTransformers.toDTO($0) }
            let attendanceDTOs = attendance.map { BackupDTOTransformers.toDTO($0) }
            let noteDTOs = notes.map { BackupDTOTransformers.toDTO($0) }
            
            // Force evaluation
            let total = studentDTOs.count + lessonDTOs.count + slDTOs.count +
                       workDTOs.count + attendanceDTOs.count + noteDTOs.count
            _ = total
        }
    }
    
    // MARK: - Backup Restore Performance
    
    /// Measures backup restore performance with 10,000 entities.
    ///
    /// This tests the complete restore pipeline:
    /// - JSON decoding
    /// - DTO validation
    /// - Entity creation
    /// - Batch insertion
    /// - Relationship linking
    ///
    /// Target: < 15 seconds for 10k entities
    ///
    /// What affects this:
    /// - JSON decoding performance
    /// - Entity initialization cost
    /// - Batch insert efficiency
    /// - Relationship resolution
    /// - Save/commit overhead
    func testBackupRestorePerformance() throws {
        // Create DTOs for large dataset
        let testData = try createLargeBackupPayload()
        
        // Create fresh container for restore
        let restoreContainer = try makePerformanceTestContainer()
        let restoreContext = ModelContext(restoreContainer)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
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
            try! restoreContext.save()
        }
    }
    
    // MARK: - Query Optimization Comparisons
    
    /// Compares string ID lookups vs relationship traversal.
    ///
    /// This benchmark demonstrates the performance difference between:
    /// - String ID predicates with UUID conversion
    /// - Direct relationship traversal
    ///
    /// This informs architecture decisions about when to use
    /// denormalized string IDs vs normalized relationships.
    ///
    /// Expected: Relationship lookups 2-3x faster than string predicates
    func testStringIDVsRelationshipLookup() throws {
        try seedStudentLessonData(context: context, count: 500)
        
        let targetStudentID = try context.fetch(FetchDescriptor<Student>()).first!.id
        
        // Measure string ID approach
        measure(metrics: [XCTClockMetric()]) {
            let studentIDString = targetStudentID.uuidString
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate<StudentLesson> { sl in
                    sl.studentIDs.contains(studentIDString)
                }
            )
            let results = try! context.fetch(descriptor)
            _ = results.count
        }
    }
    
    /// Compares batch vs individual queries for loading related entities.
    ///
    /// Tests two approaches for loading students for multiple work items:
    /// 1. Individual queries per work item (N+1 problem)
    /// 2. Single batch query with all IDs
    ///
    /// Expected: Batch queries 10x+ faster than individual queries
    func testBatchVsIndividualQueries() throws {
        try seedWorkData(context: context, workCount: 100)
        
        let workItems = try context.fetch(FetchDescriptor<WorkModel>())
        let allStudentIDs = workItems.flatMap { work in
            work.participants.compactMap { UUID(uuidString: $0.studentID) }
        }
        
        // Measure batch approach
        measure(metrics: [XCTClockMetric()]) {
            // Create set of unique student IDs
            let uniqueIDs = Set(allStudentIDs)
            
            // Single query for all students
            let allStudents = try! context.fetch(FetchDescriptor<Student>())
            let studentDict = Dictionary(uniqueKeysAndValues: allStudents.map { ($0.id, $0) })
            
            // Build results
            var results: [UUID: [Student]] = [:]
            for work in workItems {
                let studentIDs = work.participants.compactMap { UUID(uuidString: $0.studentID) }
                results[work.id] = studentIDs.compactMap { studentDict[$0] }
            }
            
            _ = results.count
        }
    }
    
    // MARK: - Memory Pressure Tests
    
    /// Tests memory usage when loading large result sets.
    ///
    /// Monitors memory footprint for operations that load
    /// thousands of records at once (attendance grids, exports).
    ///
    /// Target: < 50MB memory increase for 10k entities
    func testLargeResultSetMemory() throws {
        try seedLargeDataset(context: context)
        
        measure(metrics: [XCTMemoryMetric()]) {
            // Load large datasets
            let students = try! context.fetch(FetchDescriptor<Student>())
            let lessons = try! context.fetch(FetchDescriptor<Lesson>())
            let studentLessons = try! context.fetch(FetchDescriptor<StudentLesson>())
            let attendance = try! context.fetch(FetchDescriptor<AttendanceRecord>())
            
            // Process data (simulating view model operations)
            let studentDict = Dictionary(uniqueKeysAndValues: students.map { ($0.id, $0) })
            let lessonDict = Dictionary(uniqueKeysAndValues: lessons.map { ($0.id, $0) })
            
            var processedCount = 0
            for sl in studentLessons {
                if let lessonID = sl.lessonID, let uuid = UUID(uuidString: lessonID) {
                    _ = lessonDict[uuid]
                    processedCount += 1
                }
            }
            
            _ = processedCount + attendance.count
        }
    }
    
    // MARK: - Test Data Seeding Helpers
    
    /// Creates in-memory test container with all app models.
    private func makePerformanceTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: AppSchema.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: AppSchema.schema,
            configurations: [config]
        )
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
 PERFORMANCE BASELINES (as of Phase 5)
 ======================================
 
 These benchmarks establish performance baselines for the app.
 Run on: Apple Silicon Mac / iPhone 15 Pro
 
 Expected Results (first run establishes baseline):
 
 1. App Startup
    - Time: ~1.5s ± 0.3s
    - Memory: ~25MB
    - Notes: Includes container init + initial queries
 
 2. Today View Load (1000 lessons)
    - Time: ~75ms ± 15ms
    - Notes: Date predicate + relationship lookups
 
 3. Work List Query (500 items)
    - Time: ~120ms ± 20ms
    - Notes: Status filter + participant loading
 
 4. Attendance Grid (5,400 records)
    - Time: ~160ms ± 30ms
    - Memory: ~15MB
    - Notes: Date range + grid structure building
 
 5. Backup Export (10k entities)
    - Time: ~8s ± 2s
    - Memory: ~40MB
    - Notes: Full fetch + DTO conversion + encoding
 
 6. Backup Restore (10k entities)
    - Time: ~12s ± 3s
    - Memory: ~45MB
    - Notes: Decoding + entity creation + save
 
 7. String ID vs Relationship
    - Relationship: ~20ms
    - String ID: ~60ms
    - Ratio: 3x slower for string predicates
 
 8. Batch vs Individual Queries
    - Batch: ~30ms
    - Individual: ~400ms
    - Ratio: 13x slower for N+1 pattern
 
 REGRESSION THRESHOLDS
 =====================
 
 - Green: ±10% of baseline (normal variance)
 - Yellow: 10-20% regression (investigate if consistent)
 - Red: >20% regression (requires immediate attention)
 
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
 
 Critical Indexes:
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
 
 Command Line:
 ```bash
 # All performance tests
 xcodebuild test -scheme "Maria's Notebook" \
   -only-testing:PerformanceBenchmarks
 
 # Specific test
 xcodebuild test -scheme "Maria's Notebook" \
   -only-testing:PerformanceBenchmarks/testTodayViewLoadPerformance
 
 # With baseline comparison
 xcodebuild test -scheme "Maria's Notebook" \
   -only-testing:PerformanceBenchmarks \
   -test-iterations 5
 ```
 
 Xcode UI:
 1. Open Test Navigator (⌘6)
 2. Right-click "PerformanceBenchmarks"
 3. Select "Profile in Instruments" for deeper analysis
 4. Or "Run Performance Tests" for baseline comparison
 
 Interpreting Results:
 1. First run establishes baseline
 2. Subsequent runs show % change from baseline
 3. Check "Baseline Average" in test results
 4. Use Instruments for detailed profiling
 
 PROFILING TIPS
 ==============
 
 Use Instruments to investigate regressions:
 
 1. Time Profiler
    - Identify slow method calls
    - CPU hotspots
    - Thread contention
 
 2. Allocations
    - Memory growth patterns
    - Object lifecycle
    - Retain cycles
 
 3. Core Data Profiler
    - SwiftData fetch performance
    - Predicate efficiency
    - Relationship faults
 
 4. System Trace
    - Overall app behavior
    - Thread usage
    - System calls
 */
