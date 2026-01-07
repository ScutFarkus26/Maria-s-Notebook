import Foundation

/// Migration flags for transitioning from WorkContract to WorkModel.
/// These flags allow incremental migration while keeping the app building.
enum WorkMigrationFlags {
    /// When true, FollowUpInboxEngine uses WorkModel instead of WorkContract.
    /// Default is false to preserve current behavior.
    static var useWorkModelInInbox: Bool {
        get {
            UserDefaults.standard.bool(forKey: "WorkMigration.useWorkModelInInbox")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "WorkMigration.useWorkModelInInbox")
        }
    }
}

