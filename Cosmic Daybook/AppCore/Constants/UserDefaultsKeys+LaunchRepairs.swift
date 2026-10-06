import Foundation

// Keys for the launch repairs changed by the 2026-10-05 data model fixes, in a
// file of their own so parallel work on `UserDefaultsKeys.swift` doesn't
// collide.

nonisolated extension UserDefaultsKeys {
    /// Work ids that check-ins name but no work row has, with when each was first seen
    /// missing (`OrphanStudentGrace`, kind `.checkInWork`). Per store environment, like
    /// `orphanStudentGrace`; Reset Local Cache should clear it with that one.
    static var orphanCheckInGrace: String { CloudKitEnvironment.scoped("DataMigrations.orphanCheckInGrace") }

    /// Set once the one-time repair of notes saved with no scope blob has run and saved
    /// on this device (`DataCleanupService.repairMissingNoteScopeIndex`). Per store
    /// environment; Reset Local Cache clears it, so a fresh download is checked again.
    static var noteScopeIndexRepairDone: String { CloudKitEnvironment.scoped("DataMigrations.noteScopeIndexRepairDone") }

    /// How many launches the Keychain refused the retired-keys cleanup
    /// (`RetiredAIKeysCleanup`). Cleared once the cleanup counts as done.
    static let retiredAIKeysRefusals = "Migration.retiredAIKeysRefusals.v1"
}
