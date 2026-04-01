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
        lastName: String = "Student"
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = firstName
        student.lastName = lastName
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

    /// Saves the context, returning true on success.
    @discardableResult
    static func save(_ context: NSManagedObjectContext) -> Bool {
        context.safeSave()
    }
}
