//
//  SiriHost.swift
//  Cosmic Daybook
//
//  The notebook's half of the Siri layer. The shared files (the student
//  entity, `SiriAttendance`, the attendance intents) reach the app only
//  through `SiriHost`; Daybook Assistant defines its own with the same shape.
//

import CoreData
#if os(iOS)
import UIKit
#endif

@MainActor
enum SiriHost {
    static func stack() throws -> CoreDataStack {
        AppBootstrapping.getSharedCoreDataStack()
    }

    /// What Siri says when the notebook can't be opened (the raw error is logged).
    nonisolated static let cannotOpenMessage = "I couldn't open your class right now. Open the app and try again."

    /// The notebook is always ready: it owns its data.
    static func checkReady(in context: NSManagedObjectContext) throws {}

    /// The children Siri can name: enrolled, or leaving but still on today's
    /// roll (`SiriAttendance.nameable`), with test students hidden.
    static func roster(in context: NSManagedObjectContext) -> [CDStudent] {
        let students = DataQueryService(context: context)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: false, sortBy: CDStudent.sortByName)
        return SiriAttendance.nameable(students, in: context)
    }

    /// Who Siri looks through when no one on the roll has the name: "Open
    /// Leah" still finds a child who has left, test students aside (the roll
    /// hides them too). Not on a locked iPhone, where here and late run:
    /// "Leah isn't in the class anymore" would tell anyone nearby that she
    /// has left, which is why the Assistant never looks.
    static func formerStudents(in context: NSManagedObjectContext) -> [CDStudent] {
        #if os(iOS)
        guard UIApplication.shared.isProtectedDataAvailable else { return [] }
        #endif
        return DataQueryService(context: context)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: false, sortBy: CDStudent.sortByName)
    }

    /// Siri names children in full here: the guide's own device.
    static func displayNames(for students: [CDStudent]) -> [NSManagedObjectID: String] { [:] }

    /// Read from this device's membership, as the roll does.
    static let role: CDClassroomMembership.ClassroomRole? = nil

    /// Once arrival has closed, a child who arrives is tardy, as a tap on an
    /// iPhone tile marks them: closed on this device (Close Arrival on the
    /// roll), or anywhere else, which shows as Close Arrival's automatic
    /// absence on a record that day (an assistant's iPhone, say), unless
    /// arrival was reopened here since (`AttendanceLatePhase`).
    static func statusForHere(on day: Date, store: CDAttendanceStore) -> AttendanceStatus {
        AttendanceLatePhase.isLate(on: day, closedAnywhere: (try? store.arrivalClosed(on: day)) == true)
            ? .tardy : .present
    }

    /// Siri's Undo of a Close Arrival: this device no longer counts the day
    /// as closed here, and goes by the records again, so a Close Arrival
    /// made on another device still counts (unlike Reopen Arrival on the
    /// roll, which is on purpose).
    static func closeArrivalUndone(on day: Date) {
        AttendanceLatePhase.setLate(false, on: day)
    }

    /// Whether `day` is a school day by the guide's calendar, read from both
    /// stores: the class is her own.
    static func isSchoolDay(_ day: Date, in context: NSManagedObjectContext) -> Bool {
        !SchoolDayChecker.isNonSchoolDay(day, using: context)
    }

    /// Nothing to do: `SharedStoreOrphanGuard` files the guide's new records
    /// into the classroom share from the save itself.
    static func didSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {}
}
