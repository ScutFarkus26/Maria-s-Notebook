//
//  SiriHost.swift
//  Cosmic Daybook
//
//  The notebook's half of the Siri layer. The shared files (the student
//  entity, `SiriAttendance`, the attendance intents) reach the app only
//  through `SiriHost`; Daybook Assistant defines its own with the same shape.
//

import CoreData

@MainActor
enum SiriHost {
    static func stack() throws -> CoreDataStack {
        AppBootstrapping.getSharedCoreDataStack()
    }

    /// The notebook is always ready: it owns its data.
    static func checkReady(in context: NSManagedObjectContext) throws {}

    /// The children Siri can name: enrolled, with test students hidden, as
    /// on the roll.
    static func roster(in context: NSManagedObjectContext) -> [CDStudent] {
        DataQueryService(context: context)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true, sortBy: CDStudent.sortByName)
    }

    /// Read from this device's membership, as the roll does.
    static let role: CDClassroomMembership.ClassroomRole? = nil

    /// The notebook's roll has no arrival phase: here is present.
    static func statusForHere(on day: Date) -> AttendanceStatus { .present }

    static func arrivalReopened(on day: Date) {}

    /// Nothing to do: `SharedStoreOrphanGuard` files the guide's new records
    /// into the classroom share from the save itself.
    static func didSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {}
}
