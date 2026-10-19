// TideSyncService+Timing.swift
// The service's waits, and where it keeps the address: both stand-ins in tests.

import Foundation

extension TideSyncService {
    /// How long the service waits before each kind of run.
    struct Timing {
        var start: Duration = .seconds(5)
        /// After a to-do changes: long enough that a title still being typed
        /// isn't sent half-written.
        var change: Duration = .seconds(30)
        var settingsChange: Duration = .seconds(1)
        var interval: Duration = .seconds(180)
        var intervalWhileAway: Duration = .seconds(600)
        var tolerance: Duration = .seconds(2)
    }

    /// Where the address is kept: the Keychain, or a test's stand-in.
    struct AddressKeeper {
        var load: () throws -> TideAddress?
        var save: (TideAddress) throws -> Void
        var delete: () throws -> Void

        static let keychain = AddressKeeper(load: TideKeychain.address, save: TideKeychain.save,
                                            delete: TideKeychain.delete)
    }
}
