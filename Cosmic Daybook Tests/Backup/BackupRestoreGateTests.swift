import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// When a restore may start (#32, #38 of the 2026-10-05 hunt): never while the
/// notebook's first download from iCloud is under way, never in a notebook
/// that isn't the lead guide's, and refused before any safety copy is made.
/// Also the two lists the restore's other repairs read: the settings a
/// restore applies (#61) and the attributes an older backup can't carry (#35).
@Suite("Restore gate and lists", .serialized)
@MainActor
struct BackupRestoreGateTests {
    private typealias Restore = BackupRestoreFixtures

    /// A defaults suite of its own, so the first-download flag is this test's.
    private final class Defaults {
        let name = "BackupRestoreGateTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            defaults = try #require(UserDefaults(suiteName: name))
        }

        func remove() {
            defaults.removePersistentDomain(forName: name)
        }
    }

    @Test("The gate's reasons: not the lead guide's notebook first, then the first download")
    func gateReasons() {
        let gate = BackupRestoreGate.blocker(firstDownloadPending:role:)
        #expect(gate(false, .leadGuide) == nil)
        #expect(gate(true, .leadGuide) == BackupRestoreGate.stillDownloading)
        #expect(gate(false, .assistant) == BackupRestoreGate.notLeadGuide)
        #expect(gate(true, .assistant) == BackupRestoreGate.notLeadGuide)
    }

    /// Restores the fixture backup over `context` through the app's
    /// coordinator, expecting a refusal; returns its text and the progress lines.
    private static func refusedRestore(
        into context: NSManagedObjectContext, defaults: UserDefaults
    ) async throws -> (reason: String?, progress: [String]) {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(),
            appRouter: AppRouter(), restoreGateDefaults: defaults
        )
        let log = BackupStreamingFixtures.ProgressLog()
        do {
            _ = try await coordinator.importBackup(viewContext: context, from: url, mode: .replace) { fraction, line in
                log.append(fraction, line)
            }
            Issue.record("The restore should have been refused")
            return (nil, log.steps.map(\.message))
        } catch let refusal as BackupRestoreGate.Refusal {
            return (refusal.errorDescription, log.steps.map(\.message))
        }
    }

    @Test("While the first download is under way, a restore is refused before anything is touched")
    func refusedDuringFirstDownload() async throws {
        let suite = try Defaults()
        defer { suite.remove() }
        FirstDownloadGate.arm(defaults: suite.defaults)
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        try context.save()
        let before = try Restore.snapshot(of: context)

        let (reason, progress) = try await Self.refusedRestore(into: context, defaults: suite.defaults)

        #expect(reason == BackupRestoreGate.stillDownloading)
        #expect(progress.isEmpty, "no safety copy made, nothing read: \(progress)")
        #expect(try Restore.snapshot(of: context) == before)
        #expect(!context.hasChanges)
    }

    @Test("A notebook that joined a classroom as an assistant can't be restored")
    func refusedForAnAssistantsNotebook() async throws {
        let suite = try Defaults()
        defer { suite.remove() }
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .assistant)
        try context.save()
        let before = try Restore.snapshot(of: context)

        let (reason, progress) = try await Self.refusedRestore(into: context, defaults: suite.defaults)

        #expect(reason == BackupRestoreGate.notLeadGuide)
        #expect(progress.isEmpty, "no safety copy made, nothing read: \(progress)")
        #expect(try Restore.snapshot(of: context) == before)
    }

    @Test("A restore applies the listed settings and the per-date locks, and nothing else")
    func settingsARestoreApplies() {
        #expect(BackupPreferencesService.isBackedUp(UserDefaultsKeys.schoolYearStartMonth))
        #expect(BackupPreferencesService.isBackedUp("Attendance.locked.2026-10-05"))
        #expect(!BackupPreferencesService.isBackedUp("CloudKit.firstDownloadPending"))
        #expect(!BackupPreferencesService.isBackedUp("Attendance.lockedOut"))
    }

    @Test("Every attribute an older backup can't carry is an attribute of its entity that a restore could clear")
    func attributesAddedLaterAreReal() throws {
        let model = try CoreDataStack.sharedModel()
        for (entityName, added) in BackupFieldsAddedLater.attributes {
            let entity = try #require(model.entitiesByName[entityName], "\(entityName) is in the model")
            #expect(BackupEntityTable.names.contains(entityName), "\(entityName) is backed up")
            for (name, version) in added {
                let attribute = try #require(entity.attributesByName[name], "\(entityName).\(name) is an attribute")
                let clearable = attribute.isOptional || attribute.attributeType == .stringAttributeType
                #expect(clearable, "\(entityName).\(name): a missing value can only read as nil or \"\"")
                #expect((18...BackupWriter.formatVersion).contains(version), "\(entityName).\(name): v\(version)")
            }
        }
        #expect(BackupFieldsAddedLater.missing(from: 28, in: "AttendanceRecord").contains("note"))
        #expect(!BackupFieldsAddedLater.missing(from: 29, in: "AttendanceRecord").contains("note"))
        #expect(BackupFieldsAddedLater.missing(from: BackupWriter.formatVersion, in: "AttendanceRecord").isEmpty)
    }
}
