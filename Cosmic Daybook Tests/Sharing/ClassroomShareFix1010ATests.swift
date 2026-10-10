import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Filing into the classroom share stops or waits in more cases (bug hunt
/// 2026-10-10, Part 1 #1, #3, #5, #6): Siri's pass in a launch with no window
/// after a failed setup, a first pin from another device on a device that
/// never saw one, and an attach whose sync stops between chunks.
@Suite("Classroom share filing: stops and waits (2026-10-10)", .serialized)
@MainActor
struct ClassroomShareFix1010ATests {

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "share-fix-1010-\(UUID().uuidString)"))
    }

    private func daysOff(_ count: Int, in context: NSManagedObjectContext) -> [CDNonSchoolDay] {
        (0..<count).map { _ in
            let day = CDNonSchoolDay(context: context)
            day.date = Date()
            return day
        }
    }

    private func uri(_ object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    // MARK: - #1 Siri's pass with no window

    @Test("A launch with no window: after a setup that failed for anything but the account, Siri's pass doesn't run")
    func siriPassRefusedAfterEarlyFailedSetup() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let day = daysOff(1, in: context)[0]
        #expect(context.safeSave())

        let sync = CloudKitSyncStatusService()
        sync.syncedStoreResolver = { identifier in
            SyncedStore(identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: nil)
        }
        sync.filingHooks.wakeFiling = {}
        #expect(!sync.handlesCloudKitEvents)
        let refused = NSError(domain: "CKErrorDomain", code: 12, userInfo: [NSLocalizedDescriptionKey: "Invalid"])
        sync.receive(CloudKitEventValues(
            type: .setup, isFinished: true, succeeded: false, error: refused,
            startDate: Date(), storeIdentifier: "private-store"
        ))

        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        let lock = ClassroomShareAttachLock()
        guardian.attachLock = lock
        guardian.syncStatus = { sync }
        guardian.enqueue([day.objectID])
        let ran = PassCount()
        await guardian.attachWaiting { _ in ran.count += 1 }
        #expect(ran.count == 0, "share(_:to:) on a store whose setup failed can raise an uncatchable exception")
        #expect(guardian.pendingURIs == [uri(day)])
        #expect(!lock.isHeld)
    }

    // MARK: - #3 A first pin from another device

    @Test("A pin from elsewhere, no zone noted, after this build looked and found none: forgets what came before it")
    func firstPinAfterLookingForgets() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(2, in: context)
        #expect(context.safeSave())
        let defaults = try makeDefaults()
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        // The iPad at launch, before the Mac's Set Up reaches it.
        guardian.noteNoPinFound()
        #expect(guardian.hasLookedForPin)
        #expect(defaults.bool(forKey: SharedStoreOrphanGuard.pinLookedForKey))

        guardian.enqueue([days[0].objectID])
        try await Task.sleep(for: .milliseconds(20))
        let pinnedAt = Date()
        try await Task.sleep(for: .milliseconds(20))
        guardian.enqueue([days[1].objectID])

        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-A", pinnedAt: pinnedAt)
        #expect(guardian.pendingURIs == [uri(days[1])], "setup on the Mac took what was listed before its pin")
        #expect(guardian.waitingForImportAfterPin(notebookStoreID: "private-store"))
    }

    @Test("Looked and found none, then setup here made the pin: nothing is forgotten")
    func pinMadeHereAfterLookingKeepsTheList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(2, in: context)
        #expect(context.safeSave())
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.noteNoPinFound()
        guardian.enqueue(days.map(\.objectID))
        guardian.notePinMadeHere(zone: "zone-B")
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-B", pinnedAt: Date().addingTimeInterval(60))
        #expect(guardian.pendingURIs == days.map(uri))
    }

    @Test("A stand-in stack with sync off never counts as having looked for a pin")
    func standInStackNeverNotes() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(!stack.isCloudKitActive)
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        #expect(!guardian.hasLookedForPin, "with no marker, a pin seen later forgets nothing, as before")
    }

    // MARK: - #5 The wait the sync status asks about

    @Test("The guard says it waits for an import after a pin from elsewhere, until a pass finds one in")
    func waitingForImportIsReadable() async throws {
        let defaults = try makeDefaults()
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        #expect(!guardian.isWaitingForImportAfterPin)
        guardian.noteNoPinFound()
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-C", pinnedAt: nil)
        #expect(guardian.isWaitingForImportAfterPin)

        try await Task.sleep(for: .milliseconds(20))
        ImportWatermark.record(importStartedAt: Date(), storeIdentifier: "private-store", defaults: defaults)
        #expect(guardian.isWaitingForImportAfterPin, "reading it changes nothing")
        #expect(!guardian.waitingForImportAfterPin(notebookStoreID: "private-store"))
        #expect(!guardian.isWaitingForImportAfterPin)
    }

    // MARK: - Review round: Set Up asks again before making the share

    @Test("Right before the share is made, a hold or stop that began during setup's reads refuses it")
    func shareCreationAsksAgain() {
        let sync = CloudKitSyncStatusService()
        #expect(ClassroomSharingService.shareCreationBlocker(sync: sync) == nil)
        sync.accountNotReadyStores = ["private-store": .awaitingSetup]
        #expect(ClassroomSharingService.shareCreationBlocker(sync: sync) == .iCloudNotReadyYet)
        sync.shareFilingPausedUntilReopen = true
        #expect(ClassroomSharingService.shareCreationBlocker(sync: sync) == .iCloudNotReadyAtLaunch)

        let stopped = CloudKitSyncStatusService()
        stopped.markMirroringStopped(by: .notebook)
        #expect(ClassroomSharingService.shareCreationBlocker(sync: stopped) == .mirroringStopped)
    }

    // MARK: - #6 Stopping between chunks

    @Test("An attach stops before the next chunk once sync stops; the rest wait, untried")
    func attachStopsBetweenChunks() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(ClassroomShareAttach.chunkSize * 2 + 5, in: context)
        #expect(context.safeSave())
        let ids = days.map(\.objectID)
        let calls = ShareCalls()
        let sync = StopSwitch()
        let steps = ClassroomShareAttach.Steps(
            unshared: { $0 },
            share: { chunk in
                await calls.record(chunk)
                await sync.stop("iCloud stopped syncing") // the first chunk's export killed the delegate
            },
            stopReason: { await sync.reason }
        )
        let outcome = await ClassroomShareAttach.attach(ids, using: steps)
        #expect(await calls.all == [Array(ids[..<ClassroomShareAttach.chunkSize])])
        #expect(outcome.attached == ClassroomShareAttach.chunkSize)
        #expect(outcome.failed == Array(ids[ClassroomShareAttach.chunkSize...]))
        #expect(outcome.stoppedBecause == "iCloud stopped syncing")
        #expect(!outcome.mirroringDelegateDied, "the sync status already knows")
    }

    @Test("Stopped before the first chunk, nothing is shared; one record at a time stops too")
    func attachStopsBeforeFirstAndOneByOne() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ids = daysOff(3, in: context).map(\.objectID)
        #expect(context.safeSave())

        let held = StopSwitch()
        await held.stop("iCloud isn't ready yet")
        let none = ShareCalls()
        let refused = await ClassroomShareAttach.attach(ids, using: ClassroomShareAttach.Steps(
            unshared: { $0 }, share: { await none.record($0) }, stopReason: { await held.reason }
        ))
        #expect(await none.all.isEmpty)
        #expect(refused.failed == ids)
        #expect(refused.stoppedBecause == "iCloud isn't ready yet")

        // The chunk fails for one record; while they go one at a time, a hold starts.
        let calls = ShareCalls()
        let sync = StopSwitch()
        let outcome = await ClassroomShareAttach.attach(ids, using: ClassroomShareAttach.Steps(
            unshared: { $0 },
            share: { chunk in
                await calls.record(chunk)
                if chunk.count > 1 { throw CocoaError(.validationMissingMandatoryProperty) }
                await sync.stop("iCloud isn't ready yet")
            },
            stopReason: { await sync.reason }
        ))
        #expect(await calls.all == [ids, [ids[0]]])
        #expect(outcome.attached == 1)
        #expect(outcome.failed == Array(ids[1...]))
        #expect(outcome.stoppedBecause == "iCloud isn't ready yet")
    }
}

/// How many stand-in passes ran.
@MainActor
private final class PassCount {
    var count = 0
}

/// What a test's stand-in for `container.share(_:to:)` was asked to share.
private actor ShareCalls {
    private(set) var all: [[NSManagedObjectID]] = []
    func record(_ chunk: [NSManagedObjectID]) { all.append(chunk) }
}

/// The sync status as an attach pass sees it: a reason to stop, once set.
private actor StopSwitch {
    private(set) var reason: String?
    func stop(_ why: String) { reason = why }
}
