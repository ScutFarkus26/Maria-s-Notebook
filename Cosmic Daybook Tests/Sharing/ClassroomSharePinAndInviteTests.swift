import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Share setup and members (2026-10-05 sync hunt, #3 and the smaller "Share
/// setup and filing" list): a pin made on another device, a share whose
/// contents CloudKit couldn't report, and Stop Sharing, which keeps the share.
@Suite("Classroom share pin, invitations and Stop Sharing")
@MainActor
struct ClassroomSharePinAndInviteTests {

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "pin-invite-\(UUID().uuidString)"))
    }

    private func daysOff(_ count: Int) throws -> [CDNonSchoolDay] {
        let context = try CoreDataTestHelpers.makeContext()
        let days = (0..<count).map { _ in
            let day = CDNonSchoolDay(context: context)
            day.date = Date()
            return day
        }
        #expect(context.safeSave())
        return days
    }

    private func uri(_ object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    // MARK: - A pin made on another device

    /// Defaults on which this device had noted an earlier zone's pin, so a pin
    /// in another zone is one made elsewhere.
    private func defaultsHavingSeenAnEarlierPin() throws -> UserDefaults {
        let defaults = try makeDefaults()
        defaults.set("zone-earlier", forKey: UserDefaultsKeys.classroomSharePinSeen)
        return defaults
    }

    @Test("A pin made on another device: what this device listed before it is forgotten, once")
    func pinMadeElsewhere() async throws {
        let days = try daysOff(3)
        let guardian = SharedStoreOrphanGuard(defaults: try defaultsHavingSeenAnEarlierPin())
        guardian.enqueue([days[0].objectID])
        try await Task.sleep(for: .milliseconds(20))
        let pinnedAt = Date()
        try await Task.sleep(for: .milliseconds(20))
        guardian.enqueue([days[1].objectID])

        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-A", pinnedAt: pinnedAt)
        #expect(guardian.pendingURIs == [uri(days[1])])

        // Seen already: a later look at the same pin forgets nothing more.
        guardian.enqueue([days[2].objectID])
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-A", pinnedAt: Date().addingTimeInterval(60))
        #expect(guardian.pendingURIs == [uri(days[1]), uri(days[2])])
    }

    @Test("A pin made by setup on this device leaves its list alone")
    func pinMadeHere() throws {
        let days = try daysOff(2)
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.enqueue(days.map(\.objectID))
        guardian.notePinMadeHere(zone: "zone-B")
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-B", pinnedAt: Date().addingTimeInterval(60))
        #expect(guardian.pendingURIs == days.map(uri))
    }

    @Test("Entries listed before stamps were kept can't be dated, and stay")
    func undatedEntriesStay() throws {
        let days = try daysOff(1)
        let defaults = try defaultsHavingSeenAnEarlierPin()
        defaults.set([uri(days[0])], forKey: UserDefaultsKeys.classroomSharePendingAttach)
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        #expect(guardian.pendingEntries.map(\.stamp) == [0])
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-C", pinnedAt: Date().addingTimeInterval(60))
        #expect(guardian.pendingURIs == [uri(days[0])])
    }

    // MARK: - Bug hunt 2026-10-09, #3: a pin no build noted

    @Test("With no pin ever noted (a build before 2026-10-06), a pin forgets nothing and waits for an import")
    func unnotedPinForgetsNothing() async throws {
        let days = try daysOff(2)
        let defaults = try makeDefaults()
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        guardian.enqueue(days.map(\.objectID))
        // Listed before the pin was made: forgotten, were it noted as made elsewhere.
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-D", pinnedAt: Date().addingTimeInterval(60))

        #expect(guardian.pendingURIs == days.map(uri), "the pin may be this device's own: nothing goes")
        #expect(defaults.string(forKey: UserDefaultsKeys.classroomSharePinSeen) == "zone-D")
        #expect(defaults.object(forKey: UserDefaultsKeys.classroomSharePinSeenAt) != nil)
        #expect(guardian.waitingForImportAfterPin(notebookStoreID: "private-store"))

        try await Task.sleep(for: .milliseconds(20))
        ImportWatermark.record(importStartedAt: Date(), storeIdentifier: "private-store", defaults: defaults)
        #expect(!guardian.waitingForImportAfterPin(notebookStoreID: "private-store"))
        #expect(guardian.pendingURIs == days.map(uri))
    }

    // MARK: - Bug hunt 2026-10-09, #1: a resumed setup

    @Test("A resumed setup on a zone this device hasn't seen notes it and waits for an import after it")
    func resumedSetupOnUnseenZoneWaits() async throws {
        for defaults in [try makeDefaults(), try defaultsHavingSeenAnEarlierPin()] {
            let guardian = SharedStoreOrphanGuard(defaults: defaults)
            // An import before the pin reached this device doesn't count.
            ImportWatermark.record(
                importStartedAt: Date().addingTimeInterval(-60), storeIdentifier: "private-store", defaults: defaults
            )

            #expect(guardian.mustWaitForImportAfterPin(
                pinnedZone: "zone-E", pinnedAt: Date().addingTimeInterval(-3_600), notebookStoreID: "private-store"
            ))
            #expect(defaults.string(forKey: UserDefaultsKeys.classroomSharePinSeen) == "zone-E")
            #expect(defaults.object(forKey: UserDefaultsKeys.classroomSharePinSeenAt) != nil)

            try await Task.sleep(for: .milliseconds(20))
            ImportWatermark.record(importStartedAt: Date(), storeIdentifier: "private-store", defaults: defaults)
            #expect(!guardian.mustWaitForImportAfterPin(
                pinnedZone: "zone-E", pinnedAt: Date().addingTimeInterval(-3_600), notebookStoreID: "private-store"
            ))
        }
    }

    @Test("A resumed setup is refused in plain words while it waits, as resumePin asks, and goes ahead after")
    func resumePinRefusesWhileWaiting() async throws {
        let defaults = try makeDefaults()
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        let context = try CoreDataTestHelpers.makeContext()
        let pin = CDClassroomMembership(context: context)
        pin.role = .leadGuide
        pin.classroomZoneID = "zone-H"
        pin.joinedAt = Date().addingTimeInterval(-3_600)
        #expect(context.safeSave())

        let refusal = ClassroomSharingService.pinWaitBlocker(
            pinnedZone: "zone-H", context: context, notebookStoreID: "private-store", guardian: guardian
        )
        #expect(refusal == .classStillDownloading)
        #expect(refusal?.errorDescription == "This device is still downloading the class from iCloud. "
            + "Try again in a few minutes, or quit and reopen the notebook.")

        try await Task.sleep(for: .milliseconds(20))
        ImportWatermark.record(importStartedAt: Date(), storeIdentifier: "private-store", defaults: defaults)
        #expect(ClassroomSharingService.pinWaitBlocker(
            pinnedZone: "zone-H", context: context, notebookStoreID: "private-store", guardian: guardian
        ) == nil)
    }

    @Test("A resumed setup doesn't end the wait it found: the guard keeps waiting for the import too")
    func resumedSetupKeepsTheGuardsWait() throws {
        let defaults = try defaultsHavingSeenAnEarlierPin()
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        // The guard's pass saw the pin from another device first.
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-F", pinnedAt: Date())
        let seenAt = defaults.double(forKey: UserDefaultsKeys.classroomSharePinSeenAt)
        #expect(seenAt > 0)

        // "Add them to the share" pressed before any import since.
        #expect(guardian.mustWaitForImportAfterPin(
            pinnedZone: "zone-F", pinnedAt: Date(), notebookStoreID: "private-store"
        ))
        #expect(defaults.double(forKey: UserDefaultsKeys.classroomSharePinSeenAt) == seenAt)
        #expect(guardian.waitingForImportAfterPin(notebookStoreID: "private-store"))
    }

    @Test("A resumed setup on the pin this device made goes ahead at once")
    func resumedSetupOnOwnPinGoesAhead() throws {
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.notePinMadeHere(zone: "zone-G")
        #expect(!guardian.mustWaitForImportAfterPin(
            pinnedZone: "zone-G", pinnedAt: Date(), notebookStoreID: "private-store"
        ))
    }

    // MARK: - Bug hunt 2026-10-09, #2: no ready account when the notebook opened

    @Test("While iCloud's account holds filing, Set Up Classroom Sharing is refused first, saying why")
    func setupRefusedUnderTheHolds() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let sync = CloudKitSyncStatusService()
        // The test stack doesn't run CloudKit: that is the first thing setup minds otherwise.
        #expect(ClassroomSharingService.setupBlocker(coreDataStack: stack, sync: sync) == .cloudKitInactive)

        sync.accountNotReadyStores = ["private-store": .awaitingSetup]
        #expect(ClassroomSharingService.setupBlocker(coreDataStack: stack, sync: sync) == .iCloudNotReadyYet)
        #expect(ClassroomShareError.iCloudNotReadyYet.errorDescription
            == "iCloud isn't ready yet. Try again in a few minutes.")

        sync.shareFilingPausedUntilReopen = true
        #expect(ClassroomSharingService.setupBlocker(coreDataStack: stack, sync: sync) == .iCloudNotReadyAtLaunch)
        #expect(ClassroomShareError.iCloudNotReadyAtLaunch.errorDescription
            == "iCloud wasn't ready when the notebook opened. Quit and reopen it to finish sharing.")
    }

    // MARK: - Invitations

    @Test("Manage Sharing opens only on a share holding students; an unanswered check isn't \"no students\"")
    func invitableNeedsAnAnswer() throws {
        let unknown = #expect(throws: ClassroomShareError.self) { try ClassroomSharingService.invitable(nil) }
        #expect(Self.isContentsUnknown(unknown))

        var empty = ClassroomShareContents()
        empty.inShare = ["Student": 0, "AttendanceRecord": 12]
        let noStudents = #expect(throws: ClassroomShareError.self) { try ClassroomSharingService.invitable(empty) }
        #expect(Self.isNoStudents(noStudents))

        var shared = ClassroomShareContents()
        shared.inShare = ["Student": 24]
        #expect(try ClassroomSharingService.invitable(shared).inShare["Student"] == 24)
    }

    private static func isContentsUnknown(_ error: ClassroomShareError?) -> Bool {
        if case .shareContentsUnknown? = error { return true }
        return false
    }

    private static func isNoStudents(_ error: ClassroomShareError?) -> Bool {
        if case .shareHasNoStudents? = error { return true }
        return false
    }

    @Test("The new setup messages are plain: no CloudKit words")
    func newMessagesArePlain() {
        let errors: [ClassroomShareError] = [
            .shareContentsUnknown, .pinNotSaved, .earlierAttachStillRunning, .classStillDownloading,
            .iCloudNotReadyAtLaunch, .iCloudNotReadyYet
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            for jargon in ["CKError", "CloudKit", "record", "zone", "pin", "lock"] {
                #expect(!message.localizedCaseInsensitiveContains(jargon), "\(error): \(message)")
            }
        }
    }

    // MARK: - Stop Sharing

    /// A share made here holds only its owner: an invitee can't be made in a
    /// test (one-time-link participants need an entitlement the app lacks).
    @Test("Stop Sharing picks everyone but the owner, so the share itself stays")
    func stopSharingKeepsTheOwner() throws {
        let share = CKShare(recordZoneID: CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.share.TEST", ownerName: CKCurrentUserDefaultName
        ))
        try #require(share.participants.contains { $0.role == .owner })

        let leaving = ClassroomSharingService.membersToRemove(from: share) { _ in true }
        #expect(leaving.isEmpty)
    }
}
