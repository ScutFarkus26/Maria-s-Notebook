import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Backup v38 carries the classroom's list of names (`CDClassroomPerson`,
/// schema 16): each person's record name, role and name as typed, a cleared one
/// included. Restore matches rows on `id`, as every model-driven row does.
@Suite("Backup: classroom names", .serialized)
@MainActor
struct BackupClassroomNamesRoundTripTests {

    private typealias Support = ClassroomNamesTestSupport

    private func at(_ seconds: TimeInterval) -> Date {
        Support.at(seconds)
    }

    private func row(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDClassroomPerson? {
        try BackupTestUtil.fetchByID(CDClassroomPerson.self, id, entityName: "ClassroomPerson", in: context)
    }

    @Test("v38: the names people set, a cleared one included, survive a Replace restore")
    func namesSurviveReplace() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let guide = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), in: source)
        let ana = Support.person("_ana", "", role: .assistant, created: at(20), modified: at(30), in: source)
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        let backGuide = try #require(try row(guide.id, in: restored))
        #expect(backGuide.recordName == "_guide")
        #expect(backGuide.role == .leadGuide)
        #expect(backGuide.displayName == "Danny")
        #expect(backGuide.createdAt == at(0))
        #expect(backGuide.modifiedAt == at(10))
        let backAna = try #require(try row(ana.id, in: restored))
        #expect(backAna.recordName == "_ana")
        #expect(backAna.role == .assistant)
        #expect(backAna.displayName == "", "a cleared name stays cleared")

        let names = ClassroomNames.snapshot(in: restored)
        #expect(names.guideName == "Danny")
        #expect(names.name(forRecordName: "_ana") == nil)
        #expect(names.role(forRecordName: "_ana") == .assistant)
    }

    @Test("A Merge restore updates a row in place; a duplicate it leaves is folded by its owner")
    func mergeUpdatesAndOwnerFolds() async throws {
        // The backup holds the guide's row as the Mac wrote it.
        let rowID = UUID()
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), id: rowID, in: source)
        #expect(CoreDataTestHelpers.save(source))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        // Since then: that row renamed, and his iPad's own row written beside it.
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        Support.person("_guide", "Dan", role: .leadGuide, created: at(0), modified: at(5), id: rowID, in: target)
        Support.person("_guide", "Daniel", role: .leadGuide, created: at(40), modified: at(50), in: target)
        #expect(CoreDataTestHelpers.save(target))
        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .merge)

        let matched = try #require(try row(rowID, in: target))
        #expect(matched.displayName == "Danny", "matched on id and updated, not added again")
        #expect(target.safeFetch(CDFetchRequest(CDClassroomPerson.self)).count == 2)
        #expect(ClassroomNames.name(forRecordName: "_guide", in: target) == "Daniel", "the newest row reads")

        Support.asDevice(recordName: "_guide") {
            #expect(ClassroomNames.foldMyRows(role: .leadGuide, in: target) == 1)
        }
        #expect(target.safeSave())
        let left = target.safeFetch(CDFetchRequest(CDClassroomPerson.self))
        #expect(left.map(\.id) == [rowID], "the oldest row stays")
        #expect(left.first?.displayName == "Daniel")
    }

    @Test("A Merge restore never puts an old name back over a rename made since the backup")
    func mergeKeepsANewerRename() async throws {
        let guideID = UUID(), anaID = UUID(), beaID = UUID()
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), id: guideID, in: source)
        Support.person("_ana", "Ana", role: .assistant, created: at(0), modified: at(10), id: anaID, in: source)
        Support.person("_bea", "Bea", role: .assistant, created: at(0), modified: at(10), id: beaID, in: source)
        #expect(CoreDataTestHelpers.save(source))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        // Since the backup: Ana renamed herself, and the guide's row is the
        // same as backed up. Bea's row went missing.
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), id: guideID, in: target)
        Support.person("_ana", "Annie", role: .assistant, created: at(0), modified: at(50), id: anaID, in: target)
        #expect(CoreDataTestHelpers.save(target))
        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .merge)

        let ana = try #require(try row(anaID, in: target))
        #expect(ana.displayName == "Annie", "her newer rename stands")
        #expect(ana.modifiedAt == at(50))
        #expect(try row(guideID, in: target)?.displayName == "Danny")
        #expect(try row(beaID, in: target)?.displayName == "Bea", "a missing row comes back")
        #expect(target.safeFetch(CDFetchRequest(CDClassroomPerson.self)).count == 3)
    }
}
