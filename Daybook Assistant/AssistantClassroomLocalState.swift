import Foundation

/// What this iPhone remembers about its class outside the stores: the days
/// arrival was closed, Siri's last change (for Undo), and the sync line's
/// last save, export and import. All of it describes the class as this
/// iPhone last held it, so it goes when the class does: Leave (here, or on
/// another of her iPhones) and Rebuild from iCloud. Kept, a rebuilt class
/// said "Sending…" for marks that were deleted with the old copy, and a
/// rejoined one opened in Late.
@MainActor
enum AssistantClassroomLocalState {
    static func forget(defaults: UserDefaults = .standard) {
        AttendanceLatePhase.forget(defaults: defaults)
        SiriAttendanceChange.forget(defaults: defaults)
        for key in [
            AssistantSyncStatusView.lastSharedSaveKey,
            AssistantSyncStatusView.lastSharedExportStartKey,
            AssistantSyncStatusView.lastSharedImportEndKey
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
