import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-05 restore fixes. A Replace that stopped before its
// save told the screens the notebook was being replaced and never that it was
// over, so the app sat on "Restoring your backup…" until relaunch; a Merge
// that saved and then failed said nothing was changed.
@Suite("Backup restores end cleanly", .serialized)
@MainActor
struct BackupRestoreEndsTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Fixtures = BackupStreamingFixtures

    private struct Boom: Error {}

    private static func failing(at phase: String) -> BackupPipelineRecorder {
        let once = Fixtures.FirstTime()
        return Restore.recorder(failure: { reached in
            guard reached == phase, once.claim() else { return nil }
            return Boom()
        })
    }

    private static func backup() async throws -> (store: Fixtures.Store, url: URL) {
        let store = try Fixtures.makeStore()
        try Fixtures.seedEveryType(in: store.context, bulk: 5)
        let url = store.archiveURL("Source")
        try await Restore.writeBackup(of: store.context, to: url)
        return (store, url)
    }

    @Test("A Replace that stops before its save tells the screens it's over")
    func unsavedReplaceSignalsTheEnd() async throws {
        let (store, url) = try await Self.backup()
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let router = AppRouter()
        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: router
        )

        do {
            _ = try await BackupPipelineRecorder.$current.withValue(Self.failing(at: "import Student")) {
                try await coordinator.importBackup(
                    viewContext: target.viewContext, from: url, mode: .replace, progress: { _, _ in }
                )
            }
            Issue.record("The restore should have failed")
        } catch {}

        #expect(router.appDataDidRestore, "the restoring screen would wait for a signal that never came")
    }

    @Test("A Merge that saved and then failed doesn't say nothing was changed")
    func savedMergeSaysSo() async throws {
        let (store, url) = try await Self.backup()
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: AppRouter()
        )

        do {
            _ = try await BackupPipelineRecorder.$current.withValue(Self.failing(at: "saved")) {
                try await coordinator.importBackup(
                    viewContext: target.viewContext, from: url, mode: .merge, progress: { _, _ in }
                )
            }
            Issue.record("The restore should have failed")
        } catch BackupTransactionManager.TransactionError.importIncompleteAfterSaving(let underlying) {
            #expect(underlying is Boom)
        } catch {
            Issue.record("Expected importIncompleteAfterSaving, got \(error)")
        }
        let message = BackupTransactionManager.TransactionError.importIncompleteAfterSaving(Boom()).errorDescription
        #expect(message?.contains("nothing was changed") == false)
    }

    @Test("Notes linked to a reminder this device lacks are counted, in plain words")
    func missingReminderWarning() {
        let one = BackupWarningText.notesMissingTheirReminder(1)
        let many = BackupWarningText.notesMissingTheirReminder(3)
        #expect(BackupWarningText.plain(one) == one)
        #expect(BackupWarningText.plain(many) == many)
        #expect(many.hasPrefix("3 notes"))
    }
}
