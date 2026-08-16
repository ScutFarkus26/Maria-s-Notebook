import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Test utilities for creating in-memory Core Data stacks and seeding data.
@MainActor
enum CoreDataTestHelpers {
    /// Creates an in-memory CoreDataStack with CloudKit disabled.
    static func makeInMemoryStack() throws -> CoreDataStack {
        try CoreDataStack(enableCloudKit: false, inMemory: true)
    }

    /// Creates AppDependencies backed by an in-memory store.
    static func makeDependencies() throws -> AppDependencies {
        try AppDependencies.makeTest()
    }

    // MARK: - Seed Data

    /// Inserts a CDStudent with the given first/last name into the context.
    @discardableResult
    static func seedStudent(
        in context: NSManagedObjectContext,
        firstName: String = "Test",
        lastName: String = "Student",
        level: CDStudent.Level = .lower,
        enrollmentStatus: CDStudent.EnrollmentStatus = .enrolled,
        dateStarted: Date? = nil,
        dateWithdrawn: Date? = nil
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = firstName
        student.lastName = lastName
        student.level = level
        student.enrollmentStatus = enrollmentStatus
        student.dateStarted = dateStarted
        student.dateWithdrawn = dateWithdrawn
        return student
    }

    /// Inserts a CDNote with the given body into the context.
    @discardableResult
    static func seedNote(
        in context: NSManagedObjectContext,
        body: String = "Test note"
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        return note
    }

    /// Inserts a CDClassroomMembership with the given role and zone ID.
    @discardableResult
    static func seedClassroomMembership(
        in context: NSManagedObjectContext,
        role: CDClassroomMembership.ClassroomRole = .leadGuide,
        zoneID: String = "test-zone",
        ownerIdentity: String = "test-owner"
    ) -> CDClassroomMembership {
        let membership = CDClassroomMembership(context: context)
        membership.classroomZoneID = zoneID
        membership.role = role
        membership.ownerIdentity = ownerIdentity
        return membership
    }

    /// Inserts a CDLesson with the given name into the context.
    @discardableResult
    static func seedLesson(
        in context: NSManagedObjectContext,
        name: String = "Test Lesson",
        area: String = "Math",
        sequence: String = "Counting"
    ) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.name = name
        lesson.area = area
        lesson.sequence = sequence
        return lesson
    }

    /// Inserts a CDWorkModel with the given title and student/lesson links.
    @discardableResult
    static func seedWorkModel(
        in context: NSManagedObjectContext,
        title: String = "Test Work",
        studentID: UUID = UUID(),
        lessonID: UUID = UUID()
    ) -> CDWorkModel {
        let work = CDWorkModel(context: context)
        work.title = title
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        return work
    }

    /// Inserts a CDAttendanceRecord for the given date + student.
    @discardableResult
    static func seedAttendance(
        in context: NSManagedObjectContext,
        studentID: UUID = UUID(),
        date: Date = Date()
    ) -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.studentID = studentID.uuidString
        record.date = date
        return record
    }

    /// Saves the context, returning true on success.
    @discardableResult
    static func save(_ context: NSManagedObjectContext) -> Bool {
        context.safeSave()
    }
}
