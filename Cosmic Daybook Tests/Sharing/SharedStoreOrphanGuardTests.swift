import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The orphan guard takes only what this device just created, only the
/// classroom share's types, only from the lead guide's private store — and
/// never sweeps. These pin those choices.
@Suite("Shared-store orphan guard")
@MainActor
struct SharedStoreOrphanGuardTests {

    @Test("Only the classroom share's types, inserted into the private store, are taken")
    func takesOnlyClassroomInsertsInThePrivateStore() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = try #require(ctx.persistentStoreCoordinator?.persistentStores)
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })

        let student = CDStudent(context: ctx)
        ctx.assign(student, to: privateStore)
        let record = CDAttendanceRecord(context: ctx)
        ctx.assign(record, to: privateStore)
        let lock = CDAttendanceDayLock(context: ctx)
        ctx.assign(lock, to: privateStore)
        let lesson = CDLesson(context: ctx)
        ctx.assign(lesson, to: privateStore)
        let accepted = CDStudent(context: ctx)
        ctx.assign(accepted, to: sharedStore)
        #expect(CoreDataTestHelpers.save(ctx))

        let taken = SharedStoreOrphanGuard.classroomInserts(
            [student, record, lock, lesson, accepted], privateStore: privateStore
        )
        #expect(Set(taken) == [student.objectID, record.objectID, lock.objectID])
        #expect(SharedStoreOrphanGuard.classroomInserts([student], privateStore: nil).isEmpty)
    }

    @Test("The waiting list persists, skips repeats, and clears")
    func waitingListPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "orphan-guard-\(UUID().uuidString)"))
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let student = CDStudent(context: ctx)
        #expect(CoreDataTestHelpers.save(ctx))

        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        guardian.enqueue([student.objectID])
        guardian.enqueue([student.objectID])
        #expect(guardian.pendingURIs == [student.objectID.uriRepresentation().absoluteString])
        // A second instance on the same defaults (a relaunch) sees it too.
        #expect(SharedStoreOrphanGuard(defaults: defaults).pendingURIs.count == 1)
        let later = CDStudent(context: ctx)
        #expect(CoreDataTestHelpers.save(ctx))
        guardian.enqueue([later.objectID])
        // Setup forgets what it found and keeps what arrived during it.
        guardian.removePending([student.objectID.uriRepresentation().absoluteString])
        #expect(guardian.pendingURIs == [later.objectID.uriRepresentation().absoluteString])
        guardian.clearPending()
        #expect(guardian.pendingURIs.isEmpty)
    }

    @Test("What the share holds: counts, the outside total and the summary line")
    func contentsSummary() {
        var contents = ClassroomShareContents()
        contents.total = ["Student": 40, "AttendanceRecord": 3_908, "NonSchoolDay": 16, "AttendanceDayLock": 0]
        contents.inShare = ["Student": 40, "AttendanceRecord": 3_900, "NonSchoolDay": 16, "AttendanceDayLock": 0]
        #expect(contents.outside == 8)
        #expect(contents.summary == "40 students, 3,900 attendance records, 16 days off")
        #expect(ClassroomShareContents().summary == "0 students")
    }
}
