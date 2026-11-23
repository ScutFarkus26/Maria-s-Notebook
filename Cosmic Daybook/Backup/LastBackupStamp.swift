import Foundation
import Observation

/// When this device last made a backup by hand: the one reader and writer of
/// the time kept in UserDefaults, shared by everything that shows or sets it
/// (the Backups card, the Overview's Back Up Now, the backup status).
///
/// The time lives in UserDefaults, which Observation can't see, and it used to
/// be read and written by each `SettingsViewModel` on its own, so a backup
/// stamped by one told no view reading through another (State layer fixes
/// 2026-11, B6). Here a read is registered with Observation and every write
/// tells its readers, whichever screen made it.
///
/// It keeps no copy: every read goes to the defaults, because a restore's
/// settings and the settings import put the time there directly. A restore
/// says so afterwards (`keep(atLeast:)`), so its readers look again.
///
/// Automatic backups don't set this time; the Overview's status row takes the
/// later of it and this device's newest backup file (`SettingsDashboardViewModel`).
@Observable
final class LastBackupStamp {
    static let shared = LastBackupStamp()

    /// The key's spelling is fixed: it is in the settings export and the
    /// backup's preference lists. Not `UserDefaultsKeys.lastBackupTimeInterval`,
    /// a different key that differs only in its first letter.
    static let key = "LastBackupTimeInterval"

    private init() {}

    /// The time in the defaults now, read without telling Observation.
    private var stored: Date? {
        let interval = UserDefaults.standard.double(forKey: Self.key)
        return interval > 0 ? Date(timeIntervalSinceReferenceDate: interval) : nil
    }

    /// The last backup's time, or nil when this device has made none.
    var date: Date? {
        get {
            access(keyPath: \.date)
            return stored
        }
        set {
            withMutation(keyPath: \.date) {
                if let newValue {
                    UserDefaults.standard.set(newValue.timeIntervalSinceReferenceDate, forKey: Self.key)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.key)
                }
            }
        }
    }

    /// A backup was just saved.
    func setNow() {
        date = Date()
    }

    /// After a restore: the later of `earlier` (this device's last backup
    /// before it) and the time the restored settings carried. A restore isn't
    /// a backup, so it never says "Last backup just now" (that hid the "backup
    /// is N days old" warning), and an older backup's settings don't turn the
    /// clock back. Readers are told either way: the restore may have put a
    /// new time straight into the defaults.
    func keep(atLeast earlier: Date?) {
        withMutation(keyPath: \.date) {
            guard let earlier, (stored ?? .distantPast) < earlier else { return }
            UserDefaults.standard.set(earlier.timeIntervalSinceReferenceDate, forKey: Self.key)
        }
    }
}
