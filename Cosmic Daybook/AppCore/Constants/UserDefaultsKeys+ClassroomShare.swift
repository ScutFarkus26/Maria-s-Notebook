import Foundation

// Keys for the classroom share's waiting list and the per-store sync
// watermarks (2026-10-05 data-model fixes, Phase 1D). Device-local; never
// exported. The Daybook Assistant doesn't compile this file: nothing it
// compiles may read these.

nonisolated extension UserDefaultsKeys {
    /// When each entry of `classroomSharePendingAttach` was last added, by URI,
    /// so a record added again while an attach pass runs isn't forgotten by
    /// that pass (`SharedStoreOrphanGuard`).
    static var classroomSharePendingAttachStamps: String {
        CloudKitEnvironment.scoped("ClassroomShare.pendingAttachStamps")
    }

    /// When the last CloudKit export that finished successfully began, per
    /// store, keyed by `NSPersistentStore.identifier`: each store's history is
    /// purged only behind its own (`PersistentHistoryProcessor+Purge`). Replaces
    /// `cloudKitLastSuccessfulExportStartDate`, one date for both stores.
    static var cloudKitLastSuccessfulExportStartByStore: String {
        CloudKitEnvironment.scoped("CloudKitSync.lastSuccessfulExportStartByStore")
    }

    /// When the last CloudKit import that finished successfully began, per
    /// store, keyed by `NSPersistentStore.identifier` (`ImportWatermark`).
    static var cloudKitLastSuccessfulImportStartByStore: String {
        CloudKitEnvironment.scoped("CloudKitSync.lastSuccessfulImportStartByStore")
    }
}
