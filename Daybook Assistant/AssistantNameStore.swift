import Foundation

/// Her name, kept where the shared attendance code reads it
/// (`ClassroomIdentity.displayName`, on this iPhone) and mirrored to iCloud
/// key-value storage, so a new iPhone on her Apple Account already knows it
/// instead of asking again and marking under no name until she answers.
///
/// Key-value storage follows her Apple Account, not the guide's, so this is
/// hers alone; the guide still sees it only on the marks she makes.
enum AssistantNameStore {
    private static let key = "Assistant.displayName"

    static func save(_ name: String) {
        ClassroomIdentity.displayName = name
        let store = NSUbiquitousKeyValueStore.default
        if let saved = ClassroomIdentity.displayName {
            store.set(saved, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// Fills in a missing name from iCloud. Returns whether it did.
    @discardableResult
    static func restoreIfNeeded() -> Bool {
        guard ClassroomIdentity.displayName == nil,
              let stored = NSUbiquitousKeyValueStore.default.string(forKey: key)?.trimmed(),
              !stored.isEmpty
        else { return false }
        ClassroomIdentity.displayName = stored
        return true
    }
}
