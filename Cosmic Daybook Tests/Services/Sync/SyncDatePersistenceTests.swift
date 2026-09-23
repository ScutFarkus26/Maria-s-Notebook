import Foundation
import Testing
@testable import CosmicDaybook

/// `lastSuccessfulSync` is shown from memory; its UserDefaults copy (read only
/// at launch) is written at most once a minute. These pin that the observable
/// value never lags, that the first success writes through, and that a flush
/// leaves defaults holding exactly what is shown.
@Suite("Sync status: throttled sync-date persistence", .serialized)
@MainActor
struct SyncDatePersistenceTests {

    private let dateKey = UserDefaultsKeys.cloudKitLastSuccessfulSyncDate
    private let errorKey = UserDefaultsKeys.cloudKitLastSyncError

    private func withSavedDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let savedDate = defaults.object(forKey: dateKey)
        let savedError = defaults.object(forKey: errorKey)
        defer {
            defaults.set(savedDate, forKey: dateKey)
            defaults.set(savedError, forKey: errorKey)
        }
        try body()
    }

    @Test("First success writes through; later ones wait for the flush")
    func throttledWrites() {
        withSavedDefaults {
            let service = CloudKitSyncStatusService()
            let first = Date(timeIntervalSince1970: 1_000_000)
            let second = first.addingTimeInterval(5)

            service.recordSuccessfulSync(at: first)
            #expect(service.lastSuccessfulSync == first)
            #expect(UserDefaults.standard.double(forKey: dateKey) == first.timeIntervalSince1970)

            service.recordSuccessfulSync(at: second)
            #expect(service.lastSuccessfulSync == second)
            #expect(UserDefaults.standard.double(forKey: dateKey) == first.timeIntervalSince1970)

            service.flushPersistedSyncDate()
            #expect(UserDefaults.standard.double(forKey: dateKey) == second.timeIntervalSince1970)
        }
    }

    @Test("A user-initiated success writes through at once")
    func persistNowWritesThrough() {
        withSavedDefaults {
            let service = CloudKitSyncStatusService()
            let first = Date(timeIntervalSince1970: 2_000_000)
            service.recordSuccessfulSync(at: first)
            let manual = first.addingTimeInterval(3)
            service.recordSuccessfulSync(at: manual, persistNow: true)
            #expect(UserDefaults.standard.double(forKey: dateKey) == manual.timeIntervalSince1970)
        }
    }

    @Test("A success removes a stored error, and only touches the key when one is there")
    func errorKeyCleared() {
        withSavedDefaults {
            let service = CloudKitSyncStatusService()
            UserDefaults.standard.set("Export failed", forKey: errorKey)
            service.recordSuccessfulSync(at: Date())
            #expect(UserDefaults.standard.object(forKey: errorKey) == nil)
            service.recordSuccessfulSync(at: Date())
            #expect(UserDefaults.standard.object(forKey: errorKey) == nil)
        }
    }
}
