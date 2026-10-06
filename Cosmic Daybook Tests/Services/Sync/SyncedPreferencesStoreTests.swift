import Foundation
import Testing
@testable import CosmicDaybook

// A synced key reads through to UserDefaults when KVS holds no value for it, which is how a
// preference written before that key started syncing is still found. The one-time migration
// copied those values into KVS and left the originals in place, so the leftovers are still on
// disk — and removal has to clear them, or it uncovers the old value instead of unsetting the
// preference. The attendance day lock is the case that bites: unlocking a day removes its key.
@MainActor
@Suite("Synced preferences store")
struct SyncedPreferencesStoreTests {

    /// Prefix-matched via "Attendance.locked.", so it counts as synced, and dated well
    /// outside any real school year so it can't collide with a stored lock.
    private static let syncedKey = "Attendance.locked.1970-01-01"

    /// Runs `work` with the key absent from both stores, and leaves it that way.
    private func withKeyCleared(_ work: (SyncedPreferencesStore) -> Void) {
        let store = SyncedPreferencesStore.shared
        func clear() {
            store.remove(key: Self.syncedKey)
            // These tests seed UserDefaults directly, so they clear it directly too —
            // cleanup shouldn't depend on the behavior under test.
            UserDefaults.standard.removeObject(forKey: Self.syncedKey)
        }
        defer { clear() }
        clear()
        work(store)
    }

    @Test("The key under test really is synced, so the fallback path applies")
    func keyIsSynced() {
        #expect(SyncedPreferencesStore.shared.isSynced(key: Self.syncedKey))
    }

    @Test("A value left in UserDefaults is still read when KVS has none")
    func readsFallBackToUserDefaults() {
        withKeyCleared { store in
            UserDefaults.standard.set(true, forKey: Self.syncedKey)
            #expect(store.bool(forKey: Self.syncedKey))
        }
    }

    @Test("Removing a synced key clears the UserDefaults leftover as well as KVS")
    func removeClearsUserDefaultsLeftover() {
        withKeyCleared { store in
            // The state the migration left behind: the same value in both stores.
            UserDefaults.standard.set(true, forKey: Self.syncedKey)
            store.set(true, forKey: Self.syncedKey)
            #expect(store.bool(forKey: Self.syncedKey))

            store.remove(key: Self.syncedKey)

            #expect(!store.bool(forKey: Self.syncedKey))
            #expect(UserDefaults.standard.object(forKey: Self.syncedKey) == nil)
        }
    }

    @Test("iCloud's first values redraw the settings and announce nothing; a later change announces")
    func initialSyncRedrawsWithoutAnnouncing() {
        let store = SyncedPreferencesStore.shared
        let heard = AnnouncementCount()
        let token = NotificationCenter.default.addObserver(
            forName: .syncedPreferencesDidChange, object: store, queue: nil
        ) { _ in MainActor.assumeIsolated { heard.bump() } }
        defer { NotificationCenter.default.removeObserver(token) }

        let before = store.changeCount
        store.handleExternalChange(
            reason: NSUbiquitousKeyValueStoreInitialSyncChange, changedKeys: [Self.syncedKey]
        )
        #expect(store.changeCount == before &+ 1, "views holding a setting redraw with iCloud's values")
        #expect(heard.count == 0, "nothing answers a half-downloaded set of settings with a write")

        store.handleExternalChange(reason: NSUbiquitousKeyValueStoreServerChange, changedKeys: [Self.syncedKey])
        #expect(heard.count == 1)
    }
}

/// How many `.syncedPreferencesDidChange` announcements a test heard; they
/// are posted on the main actor here.
@MainActor
private final class AnnouncementCount {
    private(set) var count = 0
    func bump() { count += 1 }
}
