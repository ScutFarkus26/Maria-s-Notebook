// RestoredWithSyncOff.swift
// The database-error screen's restore runs only with iCloud sync off
// (`FreshNotebookRestore`), and turning sync on in Settings used to apply at
// once. The restored notebook would then upload beside the copy already in
// iCloud and could show everything twice, with nothing to say so. The restore
// now leaves a marker, and turning sync on with it set asks first.

import Foundation

nonisolated enum RestoredWithSyncOff {
    /// What turning sync on does.
    enum TurnOn: Equatable {
        /// Nothing restored with sync off: sync turns on at once.
        case now
        /// A notebook was restored with sync off: ask before turning it on.
        case askFirst
    }

    /// Set by the error screen's restore once it has succeeded.
    static func mark(in defaults: UserDefaults) {
        defaults.set(true, forKey: UserDefaultsKeys.restoredWithSyncOff)
    }

    static func isMarked(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: UserDefaultsKeys.restoredWithSyncOff)
    }

    /// Settings' sync switch turned on.
    static func turningSyncOn(in defaults: UserDefaults) -> TurnOn {
        isMarked(in: defaults) ? .askFirst : .now
    }

    /// Turn On Anyway: sync on from the next launch, and the question isn't
    /// asked again.
    static func turnOnAnyway(in defaults: UserDefaults) {
        defaults.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        defaults.removeObject(forKey: UserDefaultsKeys.restoredWithSyncOff)
    }

    // MARK: - Words

    static let questionTitle = "Turn on iCloud sync?"
    static let turnOnAnywayLabel = "Turn On Anyway"
    static let question =
        "This notebook was restored from a backup while iCloud sync was off. Turning sync on uploads "
        + "it beside the copy already in iCloud, so some things may show up twice."

    /// Added to the restore's success message.
    static let restoredNote =
        "Before you turn sync on, know that it uploads this notebook beside the copy already in iCloud, "
        + "so some things may show up twice. Settings asks before it turns sync on."
}
