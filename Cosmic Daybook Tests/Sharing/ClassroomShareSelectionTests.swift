import Foundation
import CoreData
import CloudKit
import Testing
@testable import CosmicDaybook

/// The classroom is the one share whose zone the membership row pins, and
/// nothing is guessed: taking `fetchShares(in:).first` once sent invitations to
/// an empty zone and filed new records into whichever zone came first.
@Suite("Classroom share selection")
@MainActor
struct ClassroomShareSelectionTests {

    private func share(_ zoneName: String) -> CKShare {
        CKShare(recordZoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName))
    }

    @Test("Picks the share whose zone the membership row names")
    func picksMembershipZone() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        ClassroomRepository(context: ctx).pinClassroom(zoneName: "classroom", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(ctx))

        let picked = CDClassroomMembership.classroomShare(
            among: [share("empty"), share("classroom"), share("other")],
            in: ctx
        )
        #expect(picked?.recordID.zoneID.zoneName == "classroom")
    }

    @Test("No pin means not shared yet — never the first share")
    func noPinPicksNothing() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        #expect(CDClassroomMembership.classroomShare(among: [share("a"), share("b")], in: ctx) == nil)
        #expect(CDClassroomMembership.classroomShare(among: [share("only")], in: ctx) == nil)
        #expect(CDClassroomMembership.pinnedZoneName(in: ctx) == nil)
    }

    @Test("A pin naming a zone the store doesn't hold picks nothing")
    func unmatchedPinPicksNothing() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        ClassroomRepository(context: ctx).pinClassroom(zoneName: "elsewhere", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(CDClassroomMembership.classroomShare(among: [share("only")], in: ctx) == nil)
    }

    @Test("Pinning again updates the same row; role and share read that row")
    func repinUpdatesInPlace() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let repo = ClassroomRepository(context: ctx)
        let first = repo.pinClassroom(zoneName: "old", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(ctx))
        let second = repo.pinClassroom(zoneName: "new", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(first.objectID == second.objectID)
        #expect(ctx.safeFetch(CDFetchRequest(CDClassroomMembership.self)).count == 1)
        #expect(CDClassroomMembership.pinnedZoneName(in: ctx) == "new")
        #expect(repo.fetchCurrentMembership()?.objectID == second.objectID)
    }

    @Test("Every reader agrees on the current row: the most recently pinned")
    func readersAgreeOnCurrentRow() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let repo = ClassroomRepository(context: ctx)
        let older = repo.createMembership(classroomZoneID: "older", role: .assistant, ownerIdentity: "a")
        older.joinedAt = Date(timeIntervalSinceNow: -3_600)
        older.modifiedAt = Date(timeIntervalSinceNow: -3_600)
        let newer = repo.createMembership(classroomZoneID: "newer", role: .leadGuide, ownerIdentity: "b")
        newer.modifiedAt = Date()
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(CDClassroomMembership.current(in: ctx)?.objectID == newer.objectID)
        #expect(repo.fetchCurrentMembership()?.objectID == newer.objectID)
        #expect(CDClassroomMembership.currentRole(in: ctx) == .leadGuide)
        #expect(CDClassroomMembership.pinnedZoneName(in: ctx) == "newer")
    }

    @Test("In the notebook a lead-guide row outranks a newer assistant row")
    func leadGuideRowWins() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let repo = ClassroomRepository(context: ctx)
        let guide = repo.createMembership(classroomZoneID: "classroom", role: .leadGuide, ownerIdentity: "me")
        guide.modifiedAt = Date(timeIntervalSinceNow: -3_600)
        // The guide tried the Daybook Assistant on their own Apple Account;
        // its row syncs into the notebook's private store.
        let assistant = repo.createMembership(classroomZoneID: "classroom", role: .assistant, ownerIdentity: "me")
        assistant.modifiedAt = Date()
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(CDClassroomMembership.currentRole(in: ctx) == .leadGuide)
        #expect(CDClassroomMembership.current(in: ctx)?.objectID == guide.objectID)
    }

    @Test("A notebook with no membership is its own lead guide")
    func noMembershipIsLeadGuide() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        #expect(CDClassroomMembership.currentRole(in: ctx) == .leadGuide)
    }

    // Logic-break sweep 2026-09-29, F3: with no pinned share readable, Leave
    // skipped the purge and still deleted the membership row, so the class
    // stayed on the phone with nothing to remove it.
    @Test("Leave purges the pinned share, else the only one, and refuses to guess among several")
    func leavePicksTheShareToPurge() throws {
        let pinned = share("classroom")
        #expect(try ClassroomSharingService.shareToLeave(pinned: pinned, among: [share("other"), pinned]) === pinned)

        let only = share("only")
        #expect(try ClassroomSharingService.shareToLeave(pinned: nil, among: [only]) === only)
        #expect(try ClassroomSharingService.shareToLeave(pinned: nil, among: []) == nil)
        #expect(throws: ClassroomLeaveError.self) {
            try ClassroomSharingService.shareToLeave(pinned: nil, among: [share("a"), share("b")])
        }
    }

    // Seen on a simulator 2026-09-29: CloudKit hadn't finished setting up, so
    // no share was readable; Leave deleted the membership and purged nothing,
    // and the account stayed a member of the class on iCloud.
    @Test("With the class on the device but no share readable, Leave refuses")
    func leaveRefusesAnUnreadableShare() throws {
        #expect(throws: ClassroomLeaveError.self) {
            try ClassroomSharingService.shareToLeave(pinned: nil, among: [], holdsClassroom: true)
        }
        #expect(try ClassroomSharingService.shareToLeave(pinned: nil, among: [], holdsClassroom: false) == nil)
    }
}
