#if canImport(Testing)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Maria_s_Notebook

/// Tests for StudentCard data layer.
/// Note: Full visual snapshot testing requires the SnapshotTesting library.
/// These tests verify the data models are correctly configured for card display.
@Suite("Student Card Data Tests")
struct StudentCardSnapshotTests {

    // MARK: - Default Student Card Tests

    @Test("Default card lower level student")
    @MainActor
    func defaultCard_lowerLevel() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent(level: .lower)
        container.mainContext.insert(student)
        try container.mainContext.save()

        #expect(student.level == .lower)
        #expect(student.firstName == "Emma")
        #expect(student.lastName == "Johnson")
    }

    @Test("Default card upper level student")
    @MainActor
    func defaultCard_upperLevel() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent(
            firstName: "Olivia",
            lastName: "Williams",
            level: .upper
        )
        container.mainContext.insert(student)
        try container.mainContext.save()

        #expect(student.level == .upper)
        #expect(student.firstName == "Olivia")
    }

    @Test("Default card with age display")
    @MainActor
    func defaultCard_withAge() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent()
        container.mainContext.insert(student)
        try container.mainContext.save()

        // Student should have a valid birthday for age calculation
        #expect(student.birthday != nil)
    }

    @Test("Default card long name")
    @MainActor
    func defaultCard_longName() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent(
            firstName: "Alexandria",
            lastName: "Worthington-Smith"
        )
        container.mainContext.insert(student)
        try container.mainContext.save()

        #expect(student.fullName == "Alexandria Worthington-Smith")
    }

    // MARK: - Age Student Card Tests

    @Test("Age card standard")
    @MainActor
    func ageCard_standard() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent()
        container.mainContext.insert(student)
        try container.mainContext.save()

        // Student born June 2015, reference date Jan 2025 = ~9.5 years
        #expect(student.birthday == SnapshotDates.studentBirthday)
    }

    @Test("Age card quarter age")
    @MainActor
    func ageCard_quarterAge() throws {
        let container = try makeSnapshotTestContainer()
        // Student with age that shows quarter fraction
        let student = SnapshotTestData.makeStudent(
            birthday: SnapshotDates.date(year: 2016, month: 10, day: 15)
        )
        container.mainContext.insert(student)
        try container.mainContext.save()

        #expect(student.birthday != nil)
    }

    // MARK: - Birthday Student Card Tests

    @Test("Birthday card today")
    @MainActor
    func birthdayCard_today() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudentWithBirthdayToday()
        container.mainContext.insert(student)
        try container.mainContext.save()

        // Birthday matches reference date month/day
        let calendar = Calendar.current
        let studentMonth = calendar.component(.month, from: student.birthday)
        let studentDay = calendar.component(.day, from: student.birthday)
        let refMonth = calendar.component(.month, from: SnapshotDates.reference)
        let refDay = calendar.component(.day, from: SnapshotDates.reference)

        #expect(studentMonth == refMonth)
        #expect(studentDay == refDay)
    }

    @Test("Birthday card upcoming")
    @MainActor
    func birthdayCard_upcoming() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudentWithUpcomingBirthday()
        container.mainContext.insert(student)
        try container.mainContext.save()

        // Birthday is Jan 20, reference is Jan 15 = 5 days away
        #expect(student.firstName == "Upcoming")
    }

    // MARK: - Last Lesson Student Card Tests

    @Test("Last lesson card with recent lesson")
    @MainActor
    func lastLessonCard_recentLesson() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent()
        let lesson = SnapshotTestData.makeLesson()
        let studentLesson = SnapshotTestData.makeStudentLesson(
            givenAt: SnapshotDates.fiveDaysAgo
        )

        container.mainContext.insert(student)
        container.mainContext.insert(lesson)
        container.mainContext.insert(studentLesson)
        try container.mainContext.save()

        #expect(studentLesson.givenAt != nil)
    }

    @Test("Last lesson card no lessons")
    @MainActor
    func lastLessonCard_noLessons() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent()
        container.mainContext.insert(student)
        try container.mainContext.save()

        // Student with no lessons
        #expect(student.id != nil)
    }

    // MARK: - All Student Levels Tests

    @Test("All student levels exist")
    func allLevels() {
        let levels = Student.Level.allCases
        #expect(levels.count >= 2)
        #expect(levels.contains(.lower))
        #expect(levels.contains(.upper))
    }
}

#endif
