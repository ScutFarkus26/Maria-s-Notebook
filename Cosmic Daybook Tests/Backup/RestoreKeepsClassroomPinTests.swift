import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// A restore neither writes nor clears `ClassroomMembership`: those rows pin a
/// CloudKit share zone that exists only where they were made. Restoring the
/// Development backup into the Production notebook must not pin a Development
/// zone, and a Replace restore must not make the device forget its own share.
@Suite("Restore keeps the classroom pin", .serialized)
@MainActor
struct RestoreKeepsClassroomPinTests {

    @Test("Replace mode keeps this device's pin and adds none from the backup")
    func replaceKeepsThePin() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack()
        _ = BackupTestUtil.seedBasicFixture(in: source.viewContext)
        ClassroomRepository(context: source.viewContext)
            .pinClassroom(zoneName: "development-zone", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(source.viewContext))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source.viewContext, to: url)

        let destination = try CoreDataTestHelpers.makeInMemoryStack()
        let context = destination.viewContext
        ClassroomRepository(context: context)
            .pinClassroom(zoneName: "production-zone", role: .leadGuide, ownerIdentity: "owner")
        #expect(CoreDataTestHelpers.save(context))

        try await BackupTestUtil.importCurrentBackup(from: url, into: context, mode: .replace)

        let rows = context.safeFetch(CDFetchRequest(CDClassroomMembership.self))
        #expect(rows.map(\.classroomZoneID) == ["production-zone"])
        #expect(CDClassroomMembership.pinnedZoneName(in: context) == "production-zone")
        #expect(try BackupTestUtil.count(entityName: "Student", in: context) >= 2, "the rest restored as usual")
    }
}
