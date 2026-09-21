import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Test utilities for creating in-memory Core Data stacks and seeding data.
@MainActor
enum CoreDataTestHelpers {
    /// Creates an in-memory CoreDataStack with CloudKit disabled.
    static func makeInMemoryStack() throws -> CoreDataStack {
        try CoreDataStack(enableCloudKit: false, inMemory: true)
    }

    /// The view context of a fresh in-memory stack — what a test wants when it
    /// only needs somewhere to insert. A suite that has to configure the stack
    /// (resetting a cache first, say) keeps its own helper.
    static func makeContext() throws -> NSManagedObjectContext {
        try makeInMemoryStack().viewContext
    }

    /// Parses a "yyyy-MM-dd" day string the way the MCP tools print one, so a
    /// test's dates and a tool's output agree on the calendar and the zone.
    static func day(_ iso: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: iso))
    }

    /// A context backed by two on-disk stores carrying the real Private and
    /// Shared configurations.
    ///
    /// `makeInMemoryStack` uses the unified single-store layout, where every
    /// entity has exactly one home and nothing has to be disambiguated. Store
    /// routing only becomes a question when both stores can hold a classroom
    /// entity, which is the shape this builds. Private is added first, matching
    /// production — so a test that forgets to assign still lands there.
    static func makeSplitStoreContext() throws -> NSManagedObjectContext {
        let model = try CoreDataStack.sharedModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            try coordinator.addPersistentStore(
                type: .sqlite,
                configuration: configuration,
                at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
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
