import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Backup v43 carries schema 21's `Student.bornAfterSunset`, the switch that
/// moves a child's Hebrew birthday one day on. Every v43 row says yes or no; a
/// v42 row says nothing, so it restores a new child born by day and leaves an
/// existing child's own switch.
@Suite("Backup: born after sunset (v43)", .serialized)
@MainActor
struct BackupBornAfterSunsetRoundTripTests {

    private static let studentID = UUID()

    private func student(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDStudent {
        try #require(try BackupTestUtil.fetchByID(CDStudent.self, id, entityName: "Student", in: context))
    }

    @Test("v43: the switch survives a Replace restore, on and off")
    func roundTrip() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let evening = CoreDataTestHelpers.seedStudent(in: source, firstName: "Maya", lastName: "Stone")
        evening.bornAfterSunset = true
        let daytime = CoreDataTestHelpers.seedStudent(in: source, firstName: "Ezra", lastName: "Bloom")
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        #expect(try student(evening.id, in: restored).bornAfterSunset)
        #expect(try !student(daytime.id, in: restored).bornAfterSunset)
        // v43 brought the field; later formats still carry it.
        #expect(BackupWriter.formatVersion >= 43)
        #expect(BackupReader.supportedFormatVersions.contains(42))
    }

    @Test("Every v43 row says yes or no, so a merge can turn the switch off")
    func everyRowCarriesTheSwitch() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let evening = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        evening.bornAfterSunset = true
        let daytime = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ezra", lastName: "Bloom")
        let rows = BackupServiceHelpers.toDTOs([evening, daytime])
        #expect(rows.map(\.bornAfterSunset) == [true, false])
    }

    @Test("A v42 backup restores a new child born by day")
    func v42RestoresByDay() async throws {
        let fresh = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await restore(try payload(formatVersion: 42, bornAfterSunset: nil), formatVersion: 42, into: fresh)

        let maya = try student(Self.studentID, in: fresh)
        #expect(maya.firstName == "Maya")
        #expect(!maya.bornAfterSunset)
    }

    @Test("A v42 backup merged over a child born after sunset leaves her switch on")
    func v42MergeKeepsOwnSwitch() async throws {
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = seedMaya(in: target)
        #expect(CoreDataTestHelpers.save(target))

        try await restore(try payload(formatVersion: 42, bornAfterSunset: nil), formatVersion: 42, into: target)

        #expect(maya.bornAfterSunset, "a v42 row has no switch to put over hers")
        #expect(maya.firstName == "Maya", "the rest of the row restores")
    }

    @Test("A v43 backup merged over a child born after sunset puts its own switch over hers")
    func v43MergeAppliesTheSwitch() async throws {
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = seedMaya(in: target)
        #expect(CoreDataTestHelpers.save(target))

        try await restore(try payload(formatVersion: 43, bornAfterSunset: false), formatVersion: 43, into: target)

        #expect(!maya.bornAfterSunset)
        #expect(maya.firstName == "Maya")
    }

    // MARK: - Backup rows

    /// The child as the target store holds her before the restore: born after
    /// sunset, under a name the backup's row will replace.
    private func seedMaya(in context: NSManagedObjectContext) -> CDStudent {
        let maya = CDStudent(context: context)
        maya.id = Self.studentID
        maya.firstName = "Mia"
        maya.lastName = "Stone"
        maya.bornAfterSunset = true
        return maya
    }

    /// One student row as a backup of `formatVersion` wrote it; `nil` leaves
    /// the key out, as every backup before v43 did.
    private func payload(formatVersion: Int, bornAfterSunset: Bool?) throws -> BackupPayload {
        var row = #"{"firstName":"Maya","id":"\#(Self.studentID.uuidString)","lastName":"Stone","#
            + #""level":"upper","manualOrder":0,"nextLessons":[]"#
        if let bornAfterSunset { row += #","bornAfterSunset":\#(bornAfterSunset)"# }
        row += "}"
        let decoded = BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: formatVersion, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: [
                BackupEntityEntry(entityName: "Student", storeName: "shared", count: 1, ndjson: Data((row + "\n").utf8))
            ],
            preferences: nil
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        let dto = try #require(payload.students.first, "the row decodes")
        #expect(dto.bornAfterSunset == bornAfterSunset)
        return payload
    }

    private func restore(
        _ payload: BackupPayload,
        formatVersion: Int,
        into context: NSManagedObjectContext
    ) async throws {
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: formatVersion, encrypted: false, createdAt: Date(),
                fileName: "v\(formatVersion)", entityCounts: [:]
            ),
            viewContext: context,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
    }
}
