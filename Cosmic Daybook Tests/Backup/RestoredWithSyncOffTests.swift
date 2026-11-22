import Foundation
import Testing
@testable import CosmicDaybook

/// Turning iCloud sync back on after the database-error screen restored a
/// backup with sync off (plan "Tide list clean-up 2026-11", Phase 4). The
/// restore itself setting the marker is in `ErrorScreenRestoreTests`.
@Suite("Sync after a restore with sync off", .serialized)
@MainActor
struct RestoredWithSyncOffTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "RestoredWithSyncOffTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)
        try body(defaults)
    }

    @Test("With no marker, turning sync on applies at once")
    func noMarkerTurnsOnNow() throws {
        try withDefaults { defaults in
            #expect(RestoredWithSyncOff.turningSyncOn(in: defaults) == .now)
        }
    }

    @Test("With the marker, turning sync on asks first; Turn On Anyway turns it on and clears the marker")
    func markerAsksThenClears() throws {
        try withDefaults { defaults in
            RestoredWithSyncOff.mark(in: defaults)
            #expect(RestoredWithSyncOff.turningSyncOn(in: defaults) == .askFirst)
            // Cancel changes nothing: sync stays off and the question stays.
            #expect(!CoreDataStack.syncPreferred(in: defaults))

            RestoredWithSyncOff.turnOnAnyway(in: defaults)
            #expect(CoreDataStack.syncPreferred(in: defaults))
            #expect(!RestoredWithSyncOff.isMarked(in: defaults))
            #expect(RestoredWithSyncOff.turningSyncOn(in: defaults) == .now)
        }
    }

    @Test("An ordinary restore from Settings leaves no marker, and no backup carries one")
    func ordinaryRestoreLeavesNoMarker() async throws {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.restoredWithSyncOff)
        let backup = try await BackupRestoreFixtures.makeBackup(bulk: 0)
        defer { backup.store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupRestoreFixtures.restore(backup.url, into: target.viewContext, mode: .replace)
        #expect(!RestoredWithSyncOff.isMarked(in: .standard))
        #expect(!BackupPreferencesService.isBackedUp(UserDefaultsKeys.restoredWithSyncOff))
    }

    @Test("The words are plain: no jargon in the question or the restore's message")
    func plainWords() {
        let words = RestoredWithSyncOff.question + RestoredWithSyncOff.restoredNote
            + DatabaseErrorCoordinator.restoredMessage(warnings: [])
        #expect(DatabaseErrorCoordinator.restoredMessage(warnings: []).contains(RestoredWithSyncOff.restoredNote))
        for jargon in ["sqlite", "store", "CloudKit", "cache", "marker", "flag"] {
            let found = words.range(of: "\\b\(jargon)\\b", options: [.regularExpression, .caseInsensitive])
            #expect(found == nil, "\(jargon)")
        }
    }
}
