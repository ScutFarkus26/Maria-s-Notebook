import Foundation
import CoreData
import Synchronization
import Testing
@testable import CosmicDaybook

/// What the watcher follows, as the 2026-11-05 bug hunt found it (report
/// "ParentLocker in the Assistant bug hunt 2026-11-05", #11, #15, #20): a
/// day sent by another device's send record, the guide switching to email,
/// and the duplicate cleanup's own saves. On a real (in-memory) notebook with
/// made-up children.
@Suite("ParentLocker fixes 2026-11-05: what the watcher follows")
@MainActor
struct ParentLockerFix1105AWatcherTests {

    private let morning = ParentLockerTestDevice.morning

    /// CloudKit's import, as a save's author says it.
    private static let importAuthor = "NSCloudKitMirroringDelegate.import"

    private struct Room {
        let stack: CoreDataStack
        var context: NSManagedObjectContext { stack.viewContext }
        let wren: CDStudent
        let sync: ParentLockerSync
        var wrenID: UUID { wren.id ?? UUID() }
    }

    /// Two children, ParentLocker picked, arrival not closed and nothing
    /// sent, and a sync following the notebook.
    private func room(secrets: FakeParentLockerSecrets = FakeParentLockerSecrets()) throws -> Room {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let wren = CoreDataTestHelpers.seedStudent(in: context, firstName: "Wren", lastName: "Halloway")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Juniper", lastName: "Ashby")
        var settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "", nameOrder: .firstLast, groupByLevel: false
        )
        settings.sendMethod = .parentLocker
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context)
        try context.save()
        let lateDefaults = try #require(UserDefaults(suiteName: "ParentLockerFix1105A-\(UUID().uuidString)"))
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(
            context: context, sendRecorded: { _ in }, fixedRole: .leadGuide, lateDefaults: lateDefaults
        ))
        dependencies.secrets = secrets
        dependencies.clock = FakeParentLockerClock(morning)
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.background = FakeParentLockerBackground()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.start(watching: context)
        return Room(stack: stack, wren: wren, sync: sync)
    }

    /// Saves `context` as CloudKit's import would.
    private func importSave(_ context: NSManagedObjectContext) throws {
        let author = context.transactionAuthor
        context.transactionAuthor = Self.importAuthor
        defer { context.transactionAuthor = author }
        try context.save()
    }

    /// Waits up to 5 s for the watcher's hop to the main actor.
    private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { await Task.yield() }
        return condition()
    }

    // MARK: - #11 A day sent by another device

    @Test("Another device's send record synced in releases this device's own early marks, and the line moves on (#11)")
    func sendRecordReleasesEarlyMarks() async throws {
        let room = try room()
        defer { room.sync.stop() }
        let store = CDAttendanceStore(context: room.context, role: .leadGuide)
        let record = try #require(try store.ensureRecord(for: room.wren, on: morning))
        store.updateStatus(record, to: .present)
        try room.context.save()
        #expect(await waitFor { room.sync.earlyLocal.contains(room.wrenID) }, "kept until \"after\"")
        #expect(room.sync.earlyLocalDue == nil)

        // Send with everyone marked, on the guide's Mac, synced in here.
        AttendanceEmailLog.recordSend(on: morning, role: .leadGuide, channel: .parentLocker, in: room.context)
        try importSave(room.context)
        #expect(await waitFor { room.sync.earlyLocalDue != nil })
        #expect(room.sync.earlyLocalDue == morning.addingTimeInterval(ParentLockerSync.localQuiet))
        #expect(room.sync.status.state != .readyToSend)
    }

    // MARK: - #15 A switch to email

    @Test("The guide switching to email, synced in, ends the sign-in prompt (#15)")
    func emailSyncedInEndsThePrompt() async throws {
        let room = try room(secrets: FakeParentLockerSecrets(password: nil, cookie: nil))
        defer { room.sync.stop() }
        room.sync.closeArrivalSend(on: morning)
        #expect(room.sync.awaitsSignIn)

        var settings = try #require(AttendanceEmailLog.settings(in: room.context))
        settings.sendMethod = .email
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: room.context)
        try importSave(room.context)
        #expect(await waitFor { !room.sync.awaitsSignIn })
    }

    // MARK: - #20 The duplicate cleanup

    @Test("The duplicate cleanup names its context, and the watcher passes over its saves (#20)")
    func duplicateCleanupIsPassedOver() async throws {
        #expect(ParentLockerWatcher.duplicateCleanupContextName == DeduplicationCoordinator.contextName)
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let seen = CleanupSaves()
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1)) { _, context, _ in
            let name = await context.perform { context.name }
            seen.name.withLock { $0 = name }
        }
        coordinator.persistentContainer = stack.container
        coordinator.requestDeduplication(policy: EnergyPolicy(thermalState: .nominal, isLowPowerMode: false))
        let deadline = Date().addingTimeInterval(10)
        while seen.name.withLock({ $0 }) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(seen.name.withLock { $0 } == DeduplicationCoordinator.contextName)

        let cleanup = stack.container.newBackgroundContext()
        cleanup.name = DeduplicationCoordinator.contextName
        cleanup.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        let coordinatorID = try ObjectIdentifier(#require(cleanup.persistentStoreCoordinator))
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: cleanup, queue: nil
        ) { note in
            let saved = ParentLockerWatcher.attendanceSave(note, coordinatorID: coordinatorID)
            seen.followed.withLock { $0 = saved != nil }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try cleanup.performAndWait {
            _ = NSEntityDescription.insertNewObject(forEntityName: ParentLockerWatcher.attendanceEntity, into: cleanup)
            try cleanup.save()
        }
        #expect(seen.followed.withLock { $0 } == false, "a merge isn't a change made here")
    }
}

/// What the duplicate cleanup's pass and saves showed, handed from their threads.
private nonisolated final class CleanupSaves: Sendable {
    let name = Mutex<String?>(nil)
    let followed = Mutex<Bool?>(nil)
}
