import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-02, the classroom share's setup and filing: two setups at
/// once (#30), a share whose pin never saved (#31), records left in an old
/// share (#32), and two copies of the Mac app on one waiting list (#35).
@Suite("Classroom share setup and filing fixes (2026-11-02)")
@MainActor
struct ClassroomShareFix1102DTests {

    private static let pinned = "com.apple.coredata.cloudkit.share.PINNED"
    private static let other = "com.apple.coredata.cloudkit.share.OTHER"
    private static let gone = "com.apple.coredata.cloudkit.share.GONE"

    private static func start(
        _ server: Set<String>, _ local: [String], pin: String?
    ) -> ClassroomSharingService.SetupStart {
        ClassroomSharingService.setupStart(serverZones: server, localShareZones: local, pinnedZone: pin)
    }

    // MARK: - #31 A share whose pin never saved

    @Test("A share on iCloud that no pin names, held here, is pinned and set up, not refused for good")
    func adoptsAShareWhosePinNeverSaved() {
        #expect(Self.start([Self.other], [Self.other], pin: nil) == .adopt(zone: Self.other))
        // A pin left from a share that's gone from iCloud doesn't stand in the way.
        #expect(Self.start([Self.other], [Self.other], pin: Self.gone) == .adopt(zone: Self.other))
    }

    @Test("Setup still refuses whatever it can't be sure of")
    func stillRefusesTheRest() {
        // Another device's share, not downloaded here yet: nothing to pin.
        #expect(Self.start([Self.other], [], pin: nil) == .refuse(.otherShareZonesExist(1)))
        // Two on iCloud, or the one held here isn't the one on iCloud.
        #expect(Self.start([Self.other, Self.pinned], [Self.other], pin: nil) == .refuse(.otherShareZonesExist(2)))
        #expect(Self.start([Self.other], [Self.pinned], pin: nil) == .refuse(.otherShareZonesExist(1)))
        #expect(Self.start([], [Self.other], pin: nil) == .refuse(.otherShareZonesExist(1)))
        // The pinned share on iCloud, not downloaded here yet.
        #expect(Self.start([Self.pinned], [], pin: Self.pinned) == .refuse(.shareStillSyncing))
        // The pinned share beside another.
        #expect(
            Self.start([Self.pinned, Self.other], [Self.pinned], pin: Self.pinned) == .refuse(.otherShareZonesExist(2))
        )
    }

    @Test("A first setup and a resumed one go ahead as before")
    func createsAndResumesAsBefore() {
        #expect(Self.start([], [], pin: nil) == .create)
        #expect(Self.start([], [], pin: Self.gone) == .create)
        #expect(Self.start([Self.pinned], [Self.pinned], pin: Self.pinned) == .resume(zone: Self.pinned))
    }

    // MARK: - #30 Two setups at once

    @Test("Right before the share is made, a share zone on iCloud by then refuses it")
    func creationAsksTheServerAgain() {
        let sync = CloudKitSyncStatusService()
        #expect(ClassroomSharingService.shareCreationBlocker(sync: sync, serverZones: []) == nil)
        #expect(
            ClassroomSharingService.shareCreationBlocker(sync: sync, serverZones: [Self.other])
                == .otherShareZonesExist(1)
        )
        // A stop still comes first.
        let stopped = CloudKitSyncStatusService()
        stopped.markMirroringStopped(by: .notebook)
        #expect(
            ClassroomSharingService.shareCreationBlocker(sync: stopped, serverZones: [Self.other]) == .mirroringStopped
        )
    }

    // MARK: - #32 Records in an old share

    @Test("Records in another share count apart, and Add Them to the Share isn't offered for them")
    func recordsInAnotherShareCountApart() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let students = (0..<3).map { _ in CoreDataTestHelpers.seedStudent(in: context) }
        #expect(context.safeSave())
        let ids = students.map(\.objectID)
        let zones: [NSManagedObjectID: String] = [ids[0]: Self.pinned, ids[1]: Self.other]

        let contents = try #require(
            await ClassroomSharingService.countInShare(
                ["Student": ids], inScope: ["Student": ids], zone: Self.pinned, container: stack.container
            ) { asked in zones.filter { asked.contains($0.key) } }
        )
        #expect(contents.inShare["Student"] == 1)
        #expect(contents.inScopeInOtherShare["Student"] == 1)
        #expect(contents.outside == 2, "neither is where the assistant can see it")
        #expect(contents.inOtherShare == 1)
        #expect(contents.addable == 1, "only the one in no share can be added")
        #expect(contents.mixedDuplicates == 0)
    }

    @Test("What can be added leaves out what's in another share, type by type")
    func addableLeavesOutOtherShares() {
        var contents = ClassroomShareContents()
        contents.inScope = ["Student": 10, "AttendanceRecord": 5]
        contents.inScopeAndShared = ["Student": 6, "AttendanceRecord": 5]
        contents.inScopeInOtherShare = ["Student": 3, "AttendanceRecord": 2]
        #expect(contents.outside == 4)
        // The marks are all in the share: their count in an old one can't push past what's outside.
        #expect(contents.inOtherShare == 3)
        #expect(contents.addable == 1)
        #expect(ClassroomShareContents().inOtherShareLine == nil)
    }

    @Test("The old-share line is plain")
    func oldShareLineIsPlain() throws {
        var contents = ClassroomShareContents()
        contents.inScope = ["Student": 3]
        contents.inScopeInOtherShare = ["Student": 2]
        let line = try #require(contents.inOtherShareLine)
        #expect(line.hasPrefix("2 of them are"))
        contents.inScopeInOtherShare = ["Student": 1]
        #expect(contents.inOtherShareLine?.hasPrefix("1 of them is") == true)
        #expect(!line.contains("zone") && !line.contains("CloudKit") && !line.contains("record"))
    }

    // MARK: - #35 Two copies of the Mac app on one waiting list

    @Test("A record listed by one copy while another copy's pass forgets what it took stays listed")
    func twoCopiesDontClobberTheWaitingList() throws {
        let suite = "orphan-guard-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folder = try Self.temporaryFolder()
        let secondCopy = SharedStoreOrphanGuard(defaults: defaults, listLockDirectory: folder)
        secondCopy.add(["x-coredata://taken"])
        let pendingKey = UserDefaultsKeys.classroomSharePendingAttach
        let stampsKey = UserDefaultsKeys.classroomSharePendingAttachStamps

        // The first copy's pass forgets what it attached: it reads the list,
        // takes a moment, and writes it back without that entry.
        let firstCopy = SharedStoreOrphanGuard.ListLock(directory: folder)
        let reading = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            guard let store = UserDefaults(suiteName: suite) else {
                reading.signal()
                return
            }
            firstCopy.withLock {
                let read = store.stringArray(forKey: pendingKey) ?? []
                reading.signal()
                Thread.sleep(forTimeInterval: 0.3)
                let left = read.filter { $0 != "x-coredata://taken" }
                if left.isEmpty {
                    store.removeObject(forKey: pendingKey)
                    store.removeObject(forKey: stampsKey)
                } else {
                    store.set(left, forKey: pendingKey)
                }
            }
        }
        reading.wait()
        // Meanwhile this copy lists a record it just made.
        secondCopy.add(["x-coredata://new"])
        done.wait()
        #expect(secondCopy.pendingURIs == ["x-coredata://new"])
    }

    @Test("A copy that holds the waiting list too long doesn't hang this one")
    func lockFailsOpen() throws {
        let folder = try Self.temporaryFolder()
        let stuck = SharedStoreOrphanGuard.ListLock(directory: folder)
        let impatient = SharedStoreOrphanGuard.ListLock(directory: folder, patience: .milliseconds(50))
        let holding = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            stuck.withLock {
                holding.signal()
                release.wait()
            }
            done.signal()
        }
        holding.wait()
        let started = ContinuousClock.now
        let ran = impatient.withLock { true }
        #expect(ran)
        #expect(ContinuousClock.now - started < .seconds(1))
        release.signal()
        done.wait()
    }

    private static func temporaryFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
