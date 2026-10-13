import Foundation
import CoreData
import Synchronization
import Testing
@testable import CosmicDaybook

/// The sync's reads and writes on a real (in-memory) notebook: the day as it
/// reads it, saved records back to their children, the day's ParentLocker
/// send, matches only from the guide, and a mark saved after Close Arrival
/// reaching the sync through the watcher. Made-up children.
@Suite("ParentLocker store and watcher")
@MainActor
struct ParentLockerStoreTests {

    private let morning = ParentLockerTestDevice.morning

    private struct Classroom {
        let context: NSManagedObjectContext
        let wren: CDStudent
        let june: CDStudent
        var wrenID: UUID { wren.id ?? UUID() }
        var juneID: UUID { june.id ?? UUID() }
    }

    /// Two children, ParentLocker picked, Wren marked late and June absent
    /// by Close Arrival.
    private func classroom(_ context: NSManagedObjectContext) throws -> Classroom {
        let wren = CoreDataTestHelpers.seedStudent(in: context, firstName: "Wren", lastName: "Halloway")
        let june = CoreDataTestHelpers.seedStudent(in: context, firstName: "Juniper", lastName: "Ashby")
        var settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "", nameOrder: .firstLast, groupByLevel: false
        )
        settings.sendMethod = .parentLocker
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context)
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let record = try #require(try store.ensureRecord(for: wren, on: morning))
        store.updateStatus(record, to: .tardy)
        try store.markUnmarkedAbsent(for: morning, students: [wren, june])
        try context.save()
        return Classroom(context: context, wren: wren, june: june)
    }

    @Test("A day reads the method, arrival closed, the ParentLocker send and each child's mark")
    func dayReads() throws {
        let room = try classroom(try CoreDataTestHelpers.makeContext())
        let store = ParentLockerCoreDataStore(context: room.context)
        var day = store.day(morning, withChildren: true)
        #expect(day.method == .parentLocker)
        #expect(day.site == AttendanceEmailLog.defaultParentLockerSite)
        #expect(store.site == AttendanceEmailLog.defaultParentLockerSite)
        #expect(day.arrivalClosed)
        #expect(!day.sentToParentLocker)
        #expect(day.isAfter)
        #expect(day.marks[room.wrenID]?.statusRaw == AttendanceStatus.tardy.rawValue)
        #expect(day.marks[room.juneID]?.absenceReasonRaw == AttendanceDeduplication.automaticAbsenceRaw)
        #expect(Set(day.children.map(\.id)) == [room.wrenID, room.juneID])
        #expect(day.name(of: room.juneID) == "Juniper A")

        // An email send isn't a ParentLocker send.
        AttendanceEmailLog.recordSend(on: morning, role: .leadGuide, in: room.context)
        try room.context.save()
        #expect(!store.day(morning, withChildren: false).sentToParentLocker)
        #expect(store.recordSend(on: morning))
        day = store.day(morning, withChildren: false)
        #expect(day.sentToParentLocker)
        #expect(day.children.isEmpty, "the cheap read leaves out the roll")
        #expect(AttendanceEmailLog.sends(on: morning, in: room.context).map(\.channelRaw).sorted() == [
            AttendanceSendMethod.email.rawValue, AttendanceSendMethod.parentLocker.rawValue
        ])
    }

    @Test("Saved records map back to their children, on the day asked only")
    func childrenInRecords() throws {
        let room = try classroom(try CoreDataTestHelpers.makeContext())
        let store = CDAttendanceStore(context: room.context, role: .leadGuide)
        let yesterday = morning.addingTimeInterval(-86_400)
        let earlier = try #require(try store.ensureRecord(for: room.june, on: yesterday))
        store.updateStatus(earlier, to: .present)
        try room.context.save()
        let records = try store.loadRecords(for: morning).map(\.objectID) + [earlier.objectID]
        let parentLocker = ParentLockerCoreDataStore(context: room.context)
        #expect(parentLocker.children(inRecords: records, on: morning) == [room.wrenID, room.juneID])
        #expect(parentLocker.children(inRecords: [earlier.objectID], on: morning).isEmpty)
        #expect(parentLocker.children(inRecords: [], on: morning).isEmpty)
    }

    @Test("Matches are stored on the students, and only by the lead guide")
    func matchesByGuideOnly() throws {
        let room = try classroom(try CoreDataTestHelpers.makeContext())
        let store = ParentLockerCoreDataStore(context: room.context)
        #expect(store.writeMatches([room.wrenID: "40001", room.juneID: "40002"]))
        #expect(room.wren.parentLockerID == "40001")
        #expect(store.writeMatches([room.juneID: nil]))
        #expect(room.june.parentLockerID == nil)

        let membership = CDClassroomMembership(context: room.context)
        membership.role = .assistant
        try room.context.save()
        #expect(!store.writeMatches([room.juneID: "40002"]))
        #expect(room.june.parentLockerID == nil)
    }

    @Test("A save is told apart: the app's own, or CloudKit's import; another stack's is ignored")
    func saveClassification() throws {
        #expect(ParentLockerWatcher.isImport(author: "NSCloudKitMirroringDelegate.import"))
        #expect(!ParentLockerWatcher.isImport(author: PersistentHistoryProcessor.transactionAuthor))
        #expect(!ParentLockerWatcher.isImport(author: nil))

        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let coordinator = try #require(context.persistentStoreCoordinator)
        let seen = SeenSaves()
        let coordinatorID = ObjectIdentifier(coordinator)
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil
        ) { note in
            let saved = ParentLockerWatcher.attendanceSave(note, coordinatorID: coordinatorID)
            seen.saved.withLock { $0 = saved }
            let other = ParentLockerWatcher.attendanceSave(note, coordinatorID: ObjectIdentifier(NSObject()))
            seen.elsewhere.withLock { $0 = other != nil }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let wren = CoreDataTestHelpers.seedStudent(in: context, firstName: "Wren", lastName: "Halloway")
        let record = try #require(try CDAttendanceStore(context: context, role: .leadGuide).ensureRecord(
            for: wren, on: morning
        ))
        try context.save()
        let saved = try #require(seen.saved.withLock { $0 })
        #expect(saved.records == [record.objectID])
        #expect(!saved.imported)
        #expect(!seen.elsewhere.withLock { $0 })

        // A save of nothing of attendance says nothing.
        wren.nickname = "Wrennie"
        try context.save()
        #expect(seen.saved.withLock { $0 } == nil)
    }

    @Test("A mark saved after Close Arrival reaches the sync through the watcher, 4 s out")
    func watcherFeedsTheSync() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let room = try classroom(stack.viewContext)
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(context: room.context))
        dependencies.secrets = FakeParentLockerSecrets()
        dependencies.clock = FakeParentLockerClock(morning)
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.background = FakeParentLockerBackground()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.start(watching: room.context)
        defer { sync.stop() }
        #expect(sync.isSignedIn)
        // Arrival closed with nothing sent: the guide's backstop waits 60 s.
        #expect(sync.nextWake == morning.addingTimeInterval(ParentLockerSync.backstopWait))
        AttendanceEmailLog.recordSend(on: morning, role: .leadGuide, channel: .parentLocker, in: room.context)
        try room.context.save()

        let store = CDAttendanceStore(context: room.context, role: .leadGuide)
        let record = try #require(try store.ensureRecord(for: room.june, on: morning))
        store.updateStatus(record, to: .tardy)
        try room.context.save()

        // The watcher hands the save to the main actor; wait for it, with a deadline.
        let deadline = Date().addingTimeInterval(5)
        while sync.localDue == nil, Date() < deadline { await Task.yield() }
        #expect(sync.localDue == morning.addingTimeInterval(ParentLockerSync.localQuiet))
        #expect(sync.localChanges.keys.contains(room.juneID))
    }
}

/// What the save observer saw, handed from the posting thread.
private nonisolated final class SeenSaves: Sendable {
    let saved = Mutex<(records: [NSManagedObjectID], imported: Bool)?>(nil)
    let elsewhere = Mutex(false)
}
