import Foundation
import CoreData
import CloudKit
import Testing
@testable import CosmicDaybook

/// A notebook can hold several shares; the classroom is the one whose zone the
/// membership row names. Taking `fetchShares(in:).first` once sent invitations
/// to an empty zone and filed new records into whichever zone came first.
@Suite("Classroom share selection")
@MainActor
struct ClassroomShareSelectionTests {

    private func share(_ zoneName: String) -> CKShare {
        CKShare(recordZoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName))
    }

    @Test("Picks the share whose zone the membership row names")
    func picksMembershipZone() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        ClassroomRepository(context: ctx).createMembership(
            classroomZoneID: "classroom",
            role: .leadGuide,
            ownerIdentity: "owner"
        )
        #expect(CoreDataTestHelpers.save(ctx))

        let picked = CDClassroomMembership.classroomShare(
            among: [share("empty"), share("classroom"), share("other")],
            in: ctx
        )
        #expect(picked?.recordID.zoneID.zoneName == "classroom")
    }

    @Test("Falls back to the first share when no membership names one")
    func fallsBackWithoutMembership() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        let picked = CDClassroomMembership.classroomShare(among: [share("a"), share("b")], in: ctx)
        #expect(picked?.recordID.zoneID.zoneName == "a")
    }

    @Test("A single share is the classroom's")
    func singleShare() throws {
        let ctx = try CoreDataTestHelpers.makeSplitStoreContext()
        ClassroomRepository(context: ctx).createMembership(
            classroomZoneID: "elsewhere",
            role: .leadGuide,
            ownerIdentity: "owner"
        )
        #expect(CoreDataTestHelpers.save(ctx))
        let picked = CDClassroomMembership.classroomShare(among: [share("only")], in: ctx)
        #expect(picked?.recordID.zoneID.zoneName == "only")
    }
}
