import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #7. From its second run on a device, the launch
// check-in repair deleted every check-in whose work it couldn't find, at
// once. A work row still on its way down from iCloud (a delete and re-add
// mid-sync, a slow import) read as gone, and the delete synced to every
// device. Its "has run" flag was also set before the pass saved. Orphaned
// check-ins now wait out the same grace as missing students
// (`OrphanStudentGrace`): missing on passes a day apart, with an import into
// the store between.

@Suite("Orphaned check-ins wait out a grace")
@MainActor
struct OrphanCheckInGraceTests {

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "OrphanCheckInGraceTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    /// One work with a check-in, and a check-in whose work isn't here (yet).
    private func seed(in context: NSManagedObjectContext) throws -> (orphan: CDWorkCheckIn, missingWorkID: String) {
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        CDWorkCheckIn.make(for: work, on: Date(), in: context)
        let missingWorkID = UUID().uuidString
        let orphan = CDWorkCheckIn(context: context)
        orphan.workID = missingWorkID
        orphan.date = Date()
        #expect(CoreDataTestHelpers.save(context))
        return (orphan, missingWorkID)
    }

    @Test("A check-in whose work is missing is kept the first time it's seen, even after the first run")
    func orphanKeptOnFirstSighting() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let (orphan, _) = try seed(in: context)
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)

        let report = DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: false, defaults: defaults
        )

        #expect(report.orphansDeleted == 0)
        #expect(report.orphansKept == 1)
        #expect(!orphan.isDeleted)
        #expect(context.safeFetch(CDFetchRequest(CDWorkCheckIn.self)).count == 2)
    }

    @Test("The repair itself doesn't count its first run; the pass marks it once its save goes through")
    func firstRunNotCountedByTheRepair() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        _ = try seed(in: context)

        _ = DataMigrations.repairWorkCheckInLinks(using: context, firstDownloadPending: false, defaults: defaults)

        #expect(!defaults.bool(forKey: UserDefaultsKeys.checkInLinkRepairHasRun))
    }

    @Test("The orphan goes only once its work has been missing a day with an import since")
    func orphanGoesAfterGraceAndImport() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let (orphan, missingWorkID) = try seed(in: context)
        defaults.set(true, forKey: UserDefaultsKeys.checkInLinkRepairHasRun)
        let start = Date(timeIntervalSinceReferenceDate: 780_000_000)
        func pass(at offset: TimeInterval, importedAt: Date?) -> DataCleanupService.CheckInRepairReport {
            DataMigrations.repairWorkCheckInLinks(
                using: context, firstDownloadPending: false, defaults: defaults,
                now: start.addingTimeInterval(offset), lastImport: { _ in importedAt }
            )
        }

        #expect(pass(at: 0, importedAt: nil).orphansKept == 1)
        #expect(OrphanStudentGrace.load(from: defaults, kind: .checkInWork) == [missingWorkID: start])
        // An import since it went missing, but not a day yet: kept.
        #expect(pass(at: 3_600, importedAt: start.addingTimeInterval(1_800)).orphansKept == 1)
        // A day later with no import known, or only one from before it went missing: kept.
        #expect(pass(at: 86_400, importedAt: nil).orphansKept == 1)
        #expect(pass(at: 86_400, importedAt: start.addingTimeInterval(-60)).orphansKept == 1)
        #expect(!orphan.isDeleted)

        #expect(pass(at: 86_400, importedAt: start.addingTimeInterval(1_800)).orphansDeleted == 1)
        #expect(orphan.isDeleted)
    }

    @Test("Work that arrives is relinked, and its absence is forgotten")
    func arrivingWorkIsForgotten() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let (orphan, missingWorkID) = try seed(in: context)
        _ = DataMigrations.repairWorkCheckInLinks(using: context, firstDownloadPending: false, defaults: defaults)
        #expect(!OrphanStudentGrace.load(from: defaults, kind: .checkInWork).isEmpty)

        let arrived = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        arrived.id = UUID(uuidString: missingWorkID)
        #expect(arrived.id?.uuidString == missingWorkID)
        #expect(CoreDataTestHelpers.save(context))
        let report = DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: false, defaults: defaults
        )

        #expect(report.relinked == 1)
        #expect(orphan.work === arrived)
        #expect(OrphanStudentGrace.load(from: defaults, kind: .checkInWork).isEmpty)
    }

    @Test("A lower-cased work id still finds its work")
    func lowerCasedWorkIDRelinks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = try #require(work.id?.uuidString).lowercased()
        #expect(CoreDataTestHelpers.save(context))

        let report = DataCleanupService.repairWorkCheckInLinks(using: context, deleteOrphans: true)

        #expect(report == .init(relinked: 1, orphansDeleted: 0, orphansKept: 0))
        #expect(checkIn.work === work)
    }

    @Test("A store with no work rows at all deletes no check-in")
    func noWorkRowsDeletesNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let orphan = CDWorkCheckIn(context: context)
        orphan.workID = UUID().uuidString
        #expect(CoreDataTestHelpers.save(context))

        let report = DataCleanupService.repairWorkCheckInLinks(using: context, deleteOrphans: true)

        #expect(report.orphansKept == 1)
        #expect(!orphan.isDeleted)
    }
}
