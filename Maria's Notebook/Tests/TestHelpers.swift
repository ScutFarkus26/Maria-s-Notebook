#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory

/// Creates an in-memory ModelContainer with the specified model types for testing.
/// This ensures test isolation - each test gets a fresh database.
@MainActor
func makeTestContainer(for types: [any PersistentModel.Type]) throws -> ModelContainer {
    let schema = Schema(types)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a standard container with commonly used models for most tests
@MainActor
func makeStandardTestContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        AttendanceRecord.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        Note.self,
        GroupTrack.self,
        StudentTrackEnrollment.self,
        LessonPresentation.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
    ])
}

// MARK: - Model Factories

/// Creates a test Student with sensible defaults
func makeTestStudent(
    id: UUID = UUID(),
    firstName: String = "Test",
    lastName: String = "Student",
    birthday: Date = TestCalendar.date(year: 2015, month: 6, day: 15),
    nickname: String? = nil,
    level: Student.Level = .lower,
    dateStarted: Date? = nil,
    manualOrder: Int = 0
) -> Student {
    return Student(
        id: id,
        firstName: firstName,
        lastName: lastName,
        birthday: birthday,
        nickname: nickname,
        level: level,
        dateStarted: dateStarted,
        manualOrder: manualOrder
    )
}

/// Creates a test Lesson with sensible defaults
func makeTestLesson(
    id: UUID = UUID(),
    name: String = "Test Lesson",
    subject: String = "Math",
    group: String = "Group A",
    orderInGroup: Int = 1,
    sortIndex: Int = 0,
    subheading: String = "",
    writeUp: String = ""
) -> Lesson {
    return Lesson(
        id: id,
        name: name,
        subject: subject,
        group: group,
        orderInGroup: orderInGroup,
        sortIndex: sortIndex,
        subheading: subheading,
        writeUp: writeUp
    )
}

/// Creates a test StudentLesson with sensible defaults
func makeTestStudentLesson(
    id: UUID = UUID(),
    lessonID: UUID = UUID(),
    studentIDs: [UUID] = [],
    scheduledFor: Date? = nil,
    givenAt: Date? = nil,
    isPresented: Bool = false,
    notes: String = ""
) -> StudentLesson {
    return StudentLesson(
        id: id,
        lessonID: lessonID,
        studentIDs: studentIDs,
        scheduledFor: scheduledFor,
        givenAt: givenAt,
        isPresented: isPresented,
        notes: notes
    )
}

/// Creates a StudentLesson from existing Student and Lesson objects
func makeTestStudentLesson(
    student: Student,
    lesson: Lesson,
    scheduledFor: Date? = nil,
    givenAt: Date? = nil,
    isPresented: Bool = false
) -> StudentLesson {
    return StudentLesson(
        lesson: lesson,
        students: [student],
        scheduledFor: scheduledFor,
        givenAt: givenAt,
        isPresented: isPresented
    )
}

/// Creates a test AttendanceRecord with sensible defaults
func makeTestAttendanceRecord(
    id: UUID = UUID(),
    studentID: UUID,
    date: Date = TestCalendar.date(year: 2025, month: 1, day: 15),
    status: AttendanceStatus = .unmarked,
    absenceReason: AbsenceReason = .none,
    note: String? = nil
) -> AttendanceRecord {
    return AttendanceRecord(
        id: id,
        studentID: studentID,
        date: date.normalizedDay(),
        status: status,
        absenceReason: absenceReason,
        note: note
    )
}

/// Creates a test WorkModel with sensible defaults
func makeTestWorkModel(
    id: UUID = UUID(),
    title: String = "Test Work",
    kind: WorkKind = .practiceLesson,
    completedAt: Date? = nil,
    status: WorkStatus = .active,
    assignedAt: Date = Date(),
    lastTouchedAt: Date? = nil,
    dueAt: Date? = nil,
    studentID: String = "",
    lessonID: String = ""
) -> WorkModel {
    return WorkModel(
        id: id,
        title: title,
        kind: kind,
        completedAt: completedAt,
        status: status,
        assignedAt: assignedAt,
        lastTouchedAt: lastTouchedAt,
        dueAt: dueAt,
        studentID: studentID,
        lessonID: lessonID
    )
}

/// Creates a test GroupTrack with sensible defaults
func makeTestGroupTrack(
    id: UUID = UUID(),
    subject: String = "Math",
    group: String = "Group A"
) -> GroupTrack {
    return GroupTrack(
        id: id,
        subject: subject,
        group: group
    )
}

/// Creates a test Track with sensible defaults
func makeTestTrack(
    id: UUID = UUID(),
    title: String = "Test Track"
) -> Track {
    return Track(id: id, title: title)
}

/// Creates a test TrackStep with sensible defaults
func makeTestTrackStep(
    id: UUID = UUID(),
    track: Track? = nil,
    orderIndex: Int = 0,
    lessonTemplateID: UUID? = nil
) -> TrackStep {
    return TrackStep(
        id: id,
        track: track,
        orderIndex: orderIndex,
        lessonTemplateID: lessonTemplateID
    )
}

/// Creates a test StudentTrackEnrollment with sensible defaults
func makeTestEnrollment(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    studentID: String,
    trackID: String,
    isActive: Bool = true
) -> StudentTrackEnrollment {
    return StudentTrackEnrollment(
        id: id,
        createdAt: createdAt,
        studentID: studentID,
        trackID: trackID,
        isActive: isActive
    )
}

/// Creates a test Project with sensible defaults
func makeTestProject(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    title: String = "Test Project",
    memberStudentIDs: [String] = [],
    isActive: Bool = true
) -> Project {
    return Project(
        id: id,
        createdAt: createdAt,
        title: title,
        memberStudentIDs: memberStudentIDs,
        isActive: isActive
    )
}

/// Creates a test LessonPresentation with sensible defaults
func makeTestLessonPresentation(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    studentID: String,
    lessonID: String,
    state: LessonPresentationState = .presented
) -> LessonPresentation {
    return LessonPresentation(
        id: id,
        createdAt: createdAt,
        studentID: studentID,
        lessonID: lessonID,
        state: state,
        presentedAt: Date(),
        lastObservedAt: Date(),
        masteredAt: state == .mastered ? Date() : nil
    )
}

// MARK: - Assertion Helpers

/// Asserts that two dates are equal when normalized to start of day
/// Uses AppCalendar for consistency with production code
func expectSameDay(_ date1: Date, _ date2: Date, sourceLocation: SourceLocation = #_sourceLocation) {
    let d1 = AppCalendar.startOfDay(date1)
    let d2 = AppCalendar.startOfDay(date2)
    #expect(d1 == d2, sourceLocation: sourceLocation)
}

/// Asserts that a collection contains exactly the expected count
func expectCount<T: Collection>(_ collection: T, equals expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(collection.count == expected, sourceLocation: sourceLocation)
}

// MARK: - Test Data Sets

/// Creates a set of test students with varied data
func makeTestStudentSet() -> [Student] {
    return [
        makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower, manualOrder: 1),
        makeTestStudent(firstName: "Bob", lastName: "Brown", level: .lower, manualOrder: 2),
        makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .upper, manualOrder: 3),
        makeTestStudent(firstName: "Diana", lastName: "Davis", level: .upper, manualOrder: 4),
        makeTestStudent(firstName: "Eve", lastName: "Evans", level: .lower, manualOrder: 5),
    ]
}

/// Creates a set of test lessons organized by subject and group
func makeTestLessonSet() -> [Lesson] {
    return [
        makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1),
        makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2),
        makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations", orderInGroup: 3),
        makeTestLesson(name: "Reading Basics", subject: "Language", group: "Reading", orderInGroup: 1),
        makeTestLesson(name: "Writing Practice", subject: "Language", group: "Writing", orderInGroup: 1),
    ]
}

// MARK: - Sync Testing Model Factories

/// Creates a test CalendarEvent with sensible defaults
func makeTestCalendarEvent(
    id: UUID = UUID(),
    title: String = "Test Event",
    startDate: Date = Date(),
    endDate: Date = Date().addingTimeInterval(3600),
    location: String? = nil,
    notes: String? = nil,
    isAllDay: Bool = false,
    eventKitEventID: String? = nil,
    eventKitCalendarID: String? = nil,
    lastSyncedAt: Date? = nil
) -> CalendarEvent {
    return CalendarEvent(
        id: id,
        title: title,
        startDate: startDate,
        endDate: endDate,
        location: location,
        notes: notes,
        isAllDay: isAllDay,
        eventKitEventID: eventKitEventID,
        eventKitCalendarID: eventKitCalendarID,
        lastSyncedAt: lastSyncedAt
    )
}

/// Creates a test Reminder with sensible defaults
func makeTestReminder(
    id: UUID = UUID(),
    title: String = "Test Reminder",
    notes: String? = nil,
    dueDate: Date? = nil,
    isCompleted: Bool = false,
    completedAt: Date? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    eventKitReminderID: String? = nil,
    eventKitCalendarID: String? = nil,
    lastSyncedAt: Date? = nil
) -> Reminder {
    return Reminder(
        id: id,
        title: title,
        notes: notes,
        dueDate: dueDate,
        isCompleted: isCompleted,
        completedAt: completedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        eventKitReminderID: eventKitReminderID,
        eventKitCalendarID: eventKitCalendarID,
        lastSyncedAt: lastSyncedAt
    )
}

// MARK: - Sync Testing Utilities

/// A helper class for managing UserDefaults state in tests
/// Automatically saves and restores UserDefaults state for clean test isolation
final class UserDefaultsTestHelper {
    private var savedValues: [String: Any?] = [:]
    private let keys: [String]

    /// Initialize with keys to save/restore
    init(keys: [String]) {
        self.keys = keys
    }

    /// Save current UserDefaults values for the tracked keys
    func saveState() {
        for key in keys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    /// Restore saved UserDefaults values
    func restoreState() {
        for key in keys {
            if let value = savedValues[key] {
                if let value = value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Clear all tracked keys from UserDefaults
    func clearAll() {
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Common UserDefaults keys used in CloudKit sync testing
struct CloudKitSyncTestKeys {
    static let all: [String] = [
        UserDefaultsKeys.enableCloudKitSync,
        UserDefaultsKeys.cloudKitActive,
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError
    ]
}

/// Common UserDefaults keys used in Calendar sync testing
struct CalendarSyncTestKeys {
    static let all: [String] = [
        "CalendarSync.syncCalendarIdentifiers",
        "CalendarSync.syncCalendarNames",
        "CalendarSync.syncCalendarIdentifier",
        "CalendarSync.syncCalendarName"
    ]
}

/// Common UserDefaults keys used in Reminder sync testing
struct ReminderSyncTestKeys {
    static let all: [String] = [
        "ReminderSync.syncListIdentifier",
        "ReminderSync.syncListName"
    ]
}

// MARK: - Async Testing Utilities

/// Waits for a condition to become true with timeout
/// - Parameters:
///   - timeout: Maximum time to wait in seconds
///   - interval: Polling interval in seconds
///   - condition: The condition to check
/// - Returns: True if condition became true, false if timed out
func waitFor(
    timeout: TimeInterval = 5.0,
    interval: TimeInterval = 0.1,
    condition: @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .seconds(interval))
    }
    return false
}

/// Waits for an async condition to become true with timeout
/// - Parameters:
///   - timeout: Maximum time to wait in seconds
///   - interval: Polling interval in seconds
///   - condition: The async condition to check
/// - Returns: True if condition became true, false if timed out
func waitForAsync(
    timeout: TimeInterval = 5.0,
    interval: TimeInterval = 0.1,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .seconds(interval))
    }
    return false
}

// MARK: - Test Calendar Extended

/// Extended test calendar utilities for sync testing
/// Uses AppCalendar.shared for consistency with production code
extension TestCalendar {
    /// Creates a date in the near future (for due dates)
    static func tomorrow(hour: Int = 9, minute: Int = 0) -> Date {
        let tomorrow = AppCalendar.shared.date(byAdding: .day, value: 1, to: Date())!
        return AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)!
    }

    /// Creates a date in the past (for testing old sync dates)
    static func daysAgo(_ days: Int) -> Date {
        return AppCalendar.shared.date(byAdding: .day, value: -days, to: Date())!
    }

    /// Creates a date in the future
    static func daysFromNow(_ days: Int) -> Date {
        return AppCalendar.shared.date(byAdding: .day, value: days, to: Date())!
    }

    /// Creates a date with specific hours ago (for sync timing tests)
    static func hoursAgo(_ hours: Int) -> Date {
        return AppCalendar.shared.date(byAdding: .hour, value: -hours, to: Date())!
    }

    /// Creates a date with specific minutes ago (for throttle tests)
    static func minutesAgo(_ minutes: Int) -> Date {
        return AppCalendar.shared.date(byAdding: .minute, value: -minutes, to: Date())!
    }
}

// MARK: - Sync Test Data Sets

/// Creates a set of test calendar events for sync testing
func makeTestCalendarEventSet(calendarID: String = "test-calendar") -> [CalendarEvent] {
    let now = Date()
    let startOfToday = AppCalendar.startOfDay(now)
    return [
        makeTestCalendarEvent(
            title: "Morning Meeting",
            startDate: TestCalendar.tomorrow(hour: 9),
            endDate: TestCalendar.tomorrow(hour: 10),
            location: "Conference Room A",
            eventKitEventID: "ek-event-1",
            eventKitCalendarID: calendarID
        ),
        makeTestCalendarEvent(
            title: "Lunch Break",
            startDate: TestCalendar.tomorrow(hour: 12),
            endDate: TestCalendar.tomorrow(hour: 13),
            eventKitEventID: "ek-event-2",
            eventKitCalendarID: calendarID
        ),
        makeTestCalendarEvent(
            title: "All Day Conference",
            startDate: startOfToday,
            endDate: AppCalendar.addingDays(1, to: startOfToday),
            isAllDay: true,
            eventKitEventID: "ek-event-3",
            eventKitCalendarID: calendarID
        ),
    ]
}

/// Creates a set of test reminders for sync testing
func makeTestReminderSet(listID: String = "test-reminder-list") -> [Reminder] {
    return [
        makeTestReminder(
            title: "Buy groceries",
            dueDate: TestCalendar.tomorrow(),
            eventKitReminderID: "ek-reminder-1",
            eventKitCalendarID: listID
        ),
        makeTestReminder(
            title: "Call dentist",
            notes: "Schedule annual checkup",
            eventKitReminderID: "ek-reminder-2",
            eventKitCalendarID: listID
        ),
        makeTestReminder(
            title: "Completed task",
            isCompleted: true,
            completedAt: TestCalendar.daysAgo(1),
            eventKitReminderID: "ek-reminder-3",
            eventKitCalendarID: listID
        ),
    ]
}

// MARK: - FollowUpInbox Test Helpers

@MainActor
func makeFollowUpContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkModel.self,
        WorkCheckIn.self,
        Note.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
    ])
}

/// Calculates a date that is N school days (weekdays) before today
func schoolDaysAgo(_ n: Int) -> Date {
    let today = AppCalendar.startOfDay(Date())
    var count = 0
    var cursor = today
    while count < n {
        cursor = AppCalendar.addingDays(-1, to: cursor)
        let weekday = AppCalendar.shared.component(.weekday, from: cursor)
        if weekday != 1 && weekday != 7 { count += 1 }
    }
    return cursor
}

struct FollowUpInboxItemBuilder {
    var id: String = "test:123"
    var underlyingID: UUID = UUID()
    var childID: UUID? = UUID()
    var childName: String = "Test Child"
    var title: String = "Test Lesson"
    var kind: FollowUpInboxItem.Kind = .lessonFollowUp
    var statusText: String = "Due Today"
    var ageDays: Int = 7
    var bucket: FollowUpInboxItem.Bucket = .dueToday

    func build() -> FollowUpInboxItem {
        return FollowUpInboxItem(
            id: id,
            underlyingID: underlyingID,
            childID: childID,
            childName: childName,
            title: title,
            kind: kind,
            statusText: statusText,
            ageDays: ageDays,
            bucket: bucket
        )
    }

    func withBucket(_ bucket: FollowUpInboxItem.Bucket) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.bucket = bucket
        return copy
    }

    func withAge(_ ageDays: Int) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.ageDays = ageDays
        return copy
    }

    func withChildName(_ childName: String) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.childName = childName
        return copy
    }

    func withNoChild() -> FollowUpInboxItemBuilder {
        var copy = self
        copy.childID = nil
        return copy
    }
}

/// Generic helper to test enum property mappings
func expectEnumProperty<T: Equatable, E>(
    for cases: [(E, T)],
    keyPath: KeyPath<E, T>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for (enumCase, expected) in cases {
        #expect(enumCase[keyPath: keyPath] == expected, sourceLocation: sourceLocation)
    }
}

// MARK: - Shared Test Helpers

struct TestContainerFactory {

    @MainActor
    static func makeContainer(for models: [any PersistentModel.Type]) throws -> ModelContainer {
        return try makeTestContainer(for: models)
    }

    @MainActor
    static func makeStandardContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @MainActor
    static func makeContainerWithContext(for models: [any PersistentModel.Type]) throws -> (ModelContainer, ModelContext) {
        let container = try makeContainer(for: models)
        let context = ModelContext(container)
        return (container, context)
    }
}

struct TestEntityBuilder {

    let context: ModelContext

    func buildStudent(
        firstName: String = "Test",
        lastName: String = "Student",
        birthday: Date? = nil
    ) throws -> Student {
        let student = makeTestStudent(firstName: firstName, lastName: lastName)
        if let birthday = birthday {
            student.birthday = birthday
        }
        context.insert(student)
        try context.save()
        return student
    }

    func buildLesson(
        name: String = "Test Lesson",
        subject: String = "Math",
        group: String = "Algebra"
    ) throws -> Lesson {
        let lesson = makeTestLesson(name: name, subject: subject, group: group)
        context.insert(lesson)
        try context.save()
        return lesson
    }

    func buildStudentLesson(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil
    ) throws -> StudentLesson {
        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id,
            studentIDs: students.map { $0.id },
            scheduledFor: scheduledFor,
            givenAt: givenAt
        )
        studentLesson.lesson = lesson
        studentLesson.students = students
        context.insert(studentLesson)
        try context.save()
        return studentLesson
    }

    func buildAttendanceRecord(
        studentID: UUID,
        date: Date,
        status: AttendanceStatus = .unmarked
    ) throws -> AttendanceRecord {
        let record = makeTestAttendanceRecord(studentID: studentID, date: date, status: status)
        context.insert(record)
        try context.save()
        return record
    }

    func buildWorkModel(
        studentID: String? = nil,
        lessonID: String? = nil,
        title: String = "Test Work"
    ) throws -> WorkModel {
        let work = makeTestWorkModel(
            title: title,
            studentID: studentID ?? "",
            lessonID: lessonID ?? ""
        )
        context.insert(work)
        try context.save()
        return work
    }
}

struct TestPatterns {

    static func expectSameDayNormalized(_ date1: Date, _ date2: Date, file: StaticString = #file, line: UInt = #line) {
        let normalized1 = Calendar.current.startOfDay(for: date1)
        let normalized2 = Calendar.current.startOfDay(for: date2)
        #expect(normalized1 == normalized2, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func expectThrowsError<T, E: Error>(
        _ expression: @autoclosure () throws -> T,
        ofType errorType: E.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(throws: errorType) {
            _ = try expression()
        }
    }

    static func expectEmpty<T: Collection>(
        _ collection: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(collection.isEmpty, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func expectCount<T: Collection>(
        _ collection: T,
        equals expected: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(collection.count == expected, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }
}

struct ErrorDescriptionTester {

    static func testErrorDescription<E: LocalizedError>(
        _ error: E,
        containsSubstring substring: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let description = error.errorDescription ?? ""
        #expect(description.contains(substring), sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func testErrorDescriptionEquals<E: LocalizedError>(
        _ error: E,
        expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(error.errorDescription == expected, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }
}

struct StatusCycleTester {

    @MainActor
    static func testStatusCycle(
        from: AttendanceStatus,
        to: AttendanceStatus,
        using viewModel: AttendanceViewModel,
        student: Student,
        context: ModelContext
    ) {
        // Note: This test helper is outdated - AttendanceViewModel no longer has recordsByStudent
        // Tests using this should be updated to use the new API
        let record = makeTestAttendanceRecord(studentID: student.id, status: from)
        context.insert(record)
        viewModel.cycleStatus(for: student, modelContext: context)
        // Cannot verify final status without recordsByStudent - this helper needs updating
    }
}

struct DeduplicationTester {

    static func testDeduplication<T: PersistentModel>(
        ofType type: T.Type,
        setup: (ModelContext) throws -> Void,
        deduplicateAction: (ModelContext) -> Int,
        verifyDeletedCount expectedDeletedCount: Int,
        verifyRemainingCount expectedRemainingCount: Int,
        context: ModelContext
    ) throws {
        try setup(context)
        let deletedCount = deduplicateAction(context)
        #expect(deletedCount == expectedDeletedCount)
        let remaining = context.safeFetch(FetchDescriptor<T>())
        #expect(remaining.count == expectedRemainingCount)
    }
}

#endif
