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
        WorkPlanItem.self,
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
    workType: WorkModel.WorkType = .practice,
    kind: WorkKind? = nil,
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
        workType: workType,
        completedAt: completedAt,
        kind: kind,
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
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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

#endif
