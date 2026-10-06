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

    @Test("A pin made on another device: what this device listed before it is forgotten, once")
    func pinMadeElsewhere() async throws {
        let days = try daysOff(3)
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
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
        let defaults = try makeDefaults()
        defaults.set([uri(days[0])], forKey: UserDefaultsKeys.classroomSharePendingAttach)
        let guardian = SharedStoreOrphanGuard(defaults: defaults)
        #expect(guardian.pendingEntries.map(\.stamp) == [0])
        guardian.forgetWhatSetupElsewhereTook(pinnedZone: "zone-C", pinnedAt: Date().addingTimeInterval(60))
        #expect(guardian.pendingURIs == [uri(days[0])])
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
        let errors: [ClassroomShareError] = [.shareContentsUnknown, .pinNotSaved, .earlierAttachStillRunning]
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
