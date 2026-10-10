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

    @Test("No pass runs after a setup with no account, or with a dead delegate; what waits stays listed")
    func noPassWhileSyncStopsFiling() async throws {
        let defaults = try #require(UserDefaults(suiteName: "orphan-guard-\(UUID().uuidString)"))
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let day = CDNonSchoolDay(context: ctx)
        day.date = Date()
        #expect(CoreDataTestHelpers.save(ctx))
        let uri = day.objectID.uriRepresentation().absoluteString

        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        let lock = ClassroomShareAttachLock()
        guardian.attachLock = lock
        guardian.enqueue([day.objectID])
        let ran = PassesRun()

        // Bug hunt 2026-10-09, #2: iCloud had no account when the notebook opened.
        let paused = CloudKitSyncStatusService()
        paused.shareFilingPausedUntilReopen = true
        guardian.syncStatus = { paused }
        await guardian.attachWaiting { _ in ran.count += 1 }
        #expect(ran.count == 0)
        #expect(guardian.pendingURIs == [uri])
        #expect(!lock.isHeld)

        // An account signed in but not ready yet: until its store has set up and synced.
        let notReady = CloudKitSyncStatusService()
        notReady.accountNotReadyStores = ["private-store": .awaitingSync]
        guardian.syncStatus = { notReady }
        await guardian.attachWaiting { _ in ran.count += 1 }
        #expect(ran.count == 0)
        #expect(guardian.pendingURIs == [uri])

        let stopped = CloudKitSyncStatusService()
        stopped.markMirroringStopped(by: .notebook)
        guardian.syncStatus = { stopped }
        await guardian.attachWaiting { _ in ran.count += 1 }
        #expect(ran.count == 0)
        #expect(guardian.pendingURIs == [uri])

        // With sync healthy the same pass runs.
        let healthy = CloudKitSyncStatusService()
        guardian.syncStatus = { healthy }
        await guardian.attachWaiting { taken in
            ran.count += 1
            ran.taken = taken.map(\.uri)
        }
        #expect(ran.count == 1)
        #expect(ran.taken == [uri])
        #expect(!lock.isHeld)
    }

    @Test("What the share holds: counts, the outside total and the summary line")
    func contentsSummary() {
        var contents = ClassroomShareContents()
        contents.inScope = ["Student": 40, "AttendanceRecord": 3_908, "NonSchoolDay": 16, "AttendanceDayLock": 0]
        contents.inScopeAndShared = ["Student": 40, "AttendanceRecord": 3_900, "NonSchoolDay": 16, "AttendanceDayLock": 0]
        contents.inShare = ["Student": 40, "AttendanceRecord": 3_900, "NonSchoolDay": 16, "AttendanceDayLock": 0]
        #expect(contents.outside == 8)
        #expect(contents.toRelease == 0)
        #expect(contents.summary == "40 students, 3,900 attendance marks, 16 days off")
        #expect(ClassroomShareContents().summary == "0 students")
    }

    @Test("Last year's records still in the share count as to release, never as outside")
    func contentsToRelease() {
        var contents = ClassroomShareContents()
        // 38 shared students, 24 of them this year's; 3,107 shared marks, 314 this year's.
        contents.inShare = ["Student": 38, "AttendanceRecord": 3_107, "NonSchoolDay": 40]
        contents.inScope = ["Student": 24, "AttendanceRecord": 314, "NonSchoolDay": 40]
        contents.inScopeAndShared = ["Student": 24, "AttendanceRecord": 314, "NonSchoolDay": 40]
        #expect(contents.outside == 0) // "Add Them to the Share" has nothing to offer
        #expect(contents.toRelease(of: "Student") == 14)
        #expect(contents.toRelease(of: "AttendanceRecord") == 2_793)
        #expect(contents.toRelease == 2_807)
    }

    @Test("The flush keeps only what belongs this school year")
    func flushFiltersThroughTheScope() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let cutoff = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 800_000_000))
        let scope = ClassroomShareScope(cutoff: cutoff)
        let lastYear = cutoff.addingTimeInterval(-100 * 86_400)
        let thisYear = cutoff.addingTimeInterval(10 * 86_400)

        let current = CDStudent(context: ctx)
        let departed = CDStudent(context: ctx)
        departed.enrollmentStatus = .withdrawn
        departed.dateWithdrawn = lastYear
        let currentOld = CDAttendanceRecord(context: ctx)
        currentOld.studentID = try #require(current.id?.uuidString)
        currentOld.date = lastYear
        let currentNew = CDAttendanceRecord(context: ctx)
        currentNew.studentID = try #require(current.id?.uuidString.lowercased())
        currentNew.date = thisYear
        let departedOld = CDAttendanceRecord(context: ctx)
        departedOld.studentID = try #require(departed.id?.uuidString)
        departedOld.date = lastYear
        let dayOff = CDNonSchoolDay(context: ctx)
        dayOff.date = lastYear
        #expect(CoreDataTestHelpers.save(ctx))

        let all = [current, departed, currentOld, currentNew, departedOld, dayOff]
        let kept = await SharedStoreOrphanGuard.existingIDs(
            for: all.map { $0.objectID.uriRepresentation().absoluteString },
            container: stack.container,
            scope: scope
        )
        #expect(Set(kept) == [current.objectID, currentNew.objectID, dayOff.objectID])
    }
}

/// What a test's stand-in passes did.
@MainActor
private final class PassesRun {
    var count = 0
    var taken: [String] = []
}
