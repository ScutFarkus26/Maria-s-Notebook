import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #56: the first-download watch was tied to the sync status
// service's `configure`, which the window's bootstrap reaches seconds into a
// launch (and never without a window), so an import that finished first left
// the gate armed; and with iCloud signed out it stayed armed for good. The
// watch now starts when the stack loads and needs nothing `configure` sets.

@Suite("First download: the watch from load")
@MainActor
struct FirstDownloadWatchTests {

    private func armedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "FirstDownloadWatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        FirstDownloadGate.arm(defaults: defaults)
        return (defaults, suiteName)
    }

    @Test("The private store's finished import opens the gate, with no sync service configured")
    func privateImportOpensGate() throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()

        let opened = CloudKitSyncStatusService.finishFirstDownloadIfNeeded(
            importedStoreIdentifier: "private-store",
            privateStoreIdentifier: "private-store",
            context: context,
            defaults: defaults
        )

        #expect(opened)
        #expect(!FirstDownloadGate.isPending(defaults: defaults))
    }

    @Test("Another store's import, or a stack with no private store, leaves the gate armed")
    func otherImportsLeaveGateArmed() throws {
        let (defaults, suiteName) = try armedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()

        #expect(!CloudKitSyncStatusService.finishFirstDownloadIfNeeded(
            importedStoreIdentifier: "shared-store", privateStoreIdentifier: "private-store",
            context: context, defaults: defaults
        ))
        #expect(!CloudKitSyncStatusService.finishFirstDownloadIfNeeded(
            importedStoreIdentifier: nil, privateStoreIdentifier: nil, context: context, defaults: defaults
        ))
        #expect(FirstDownloadGate.isPending(defaults: defaults))
    }

    @Test("With sync on and no iCloud account signed in, nothing will download")
    func signedOutMeansNothingWillDownload() {
        #expect(FirstDownloadGate.nothingWillDownload(accountStatus: .noAccount, cloudKitActive: true))
        for status: CKAccountStatus in [.available, .couldNotDetermine, .restricted, .temporarilyUnavailable] {
            #expect(!FirstDownloadGate.nothingWillDownload(accountStatus: status, cloudKitActive: true))
        }
        // Sync off is the launch's business (`updateFirstDownloadGate`), not this.
        #expect(!FirstDownloadGate.nothingWillDownload(accountStatus: .noAccount, cloudKitActive: false))
    }
}
