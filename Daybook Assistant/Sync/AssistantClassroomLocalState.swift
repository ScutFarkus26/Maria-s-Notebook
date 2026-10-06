import Foundation

/// What this iPhone remembers about its class outside the stores: the days
/// arrival was closed, Siri's last change (for Undo), the sync line's last
/// save, export and import, the share zone its class's share was seen in,
/// and the marks still waiting to go into the share. All of it describes the
/// class as this iPhone last held it, so it goes when the class does: Leave
/// (here, or on another of her iPhones) and Rebuild from iCloud. Kept, a
/// rebuilt class said "Sending…" for marks that were deleted with the old
/// copy, a rejoined one opened in Late, and the waiting marks went into
/// whichever class she joined next.
@MainActor
enum AssistantClassroomLocalState {
    /// The pinned share zone whose share this iPhone has found in its shared
    /// store. Only a share seen here can be missed: before the class first
    /// arrives on a new iPhone there is no share yet either, and that's not
    /// being taken out of the class (`AssistantBootstrapper.checkStillInClass`).
    static var shareSeenZoneKey: String { CloudKitEnvironment.scoped("Assistant.classroomShareSeenZone") }

    static func noteShareSeen(inZone zone: String, defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: shareSeenZoneKey) != zone else { return }
        defaults.set(zone, forKey: shareSeenZoneKey)
    }

    static func sawShare(inZone zone: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: shareSeenZoneKey) == zone
    }

    static func forget(defaults: UserDefaults = .standard) {
        AttendanceLatePhase.forget(defaults: defaults)
        SiriAttendanceChange.forget(defaults: defaults)
        AssistantSyncRecord.forget(defaults: defaults)
        for key in [shareSeenZoneKey, AssistantShareAttacher.listKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
