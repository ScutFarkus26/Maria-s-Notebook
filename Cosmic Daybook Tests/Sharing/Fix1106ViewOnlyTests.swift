import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-11-06 Daybook Assistant bug hunt, #7: a View only saved under the
// old rule, which also counted the store-wide `canModifyManagedObjects` and
// told assistants the share let make changes they were View only, cleared
// only when the share said read-write. The answer now lives under a new key;
// an old one is kept as "not confirmed": it still holds writes back, and the
// first read of the share drops it (docs/Reviews/Daybook Assistant bug hunt
// 2026-11-06.md).
@Suite("View only re-checked after the 2026-11-06 rule change", .serialized)
@MainActor
struct Fix1106ViewOnlyTests {

    @Test("Only an answer under the new key is confirmed; one under the old key alone is not")
    func savedAnswers() {
        let defaults = Self.makeDefaults()
        #expect(ClassroomPermissions.viewOnlyKey != ClassroomPermissions.oldViewOnlyKey)
        #expect(ClassroomPermissions.savedViewOnly(in: defaults) == (false, false))

        // Before: the old key was the key, and its true held for good.
        defaults.set(true, forKey: ClassroomPermissions.oldViewOnlyKey)
        #expect(ClassroomPermissions.savedViewOnly(in: defaults) == (true, true), "still holds writes back")

        defaults.set(true, forKey: ClassroomPermissions.viewOnlyKey)
        #expect(ClassroomPermissions.savedViewOnly(in: defaults) == (true, false))
    }

    @Test("An unconfirmed View only blocks writes until a share read drops it; a confirmed one stays")
    func unconfirmedIsDroppedAtTheFirstRead() {
        let saved = SavedViewOnly()
        defer { saved.restore() }

        // Carried over from the old key: no write gets through in the gap.
        ClassroomPermissions.shareIsViewOnly = true
        ClassroomPermissions.viewOnlyIsUnconfirmed = true
        #expect(!ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant))

        #expect(ClassroomPermissions.dropUnconfirmedViewOnly())
        #expect(!ClassroomPermissions.shareIsViewOnly)
        #expect(ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant))
        #expect(!ClassroomPermissions.dropUnconfirmedViewOnly(), "only once")

        // An answer read under the new rule isn't dropped by a read that says nothing.
        ClassroomPermissions.shareIsViewOnly = true
        #expect(!ClassroomPermissions.viewOnlyIsUnconfirmed)
        #expect(!ClassroomPermissions.dropUnconfirmedViewOnly())
        #expect(ClassroomPermissions.shareIsViewOnly)
        #expect(UserDefaults.standard.bool(forKey: ClassroomPermissions.viewOnlyKey))
    }

    @Test("Any answer clears the old key and the unconfirmed mark")
    func answerReplacesTheOldKey() {
        let saved = SavedViewOnly()
        defer { saved.restore() }
        UserDefaults.standard.set(true, forKey: ClassroomPermissions.oldViewOnlyKey)
        ClassroomPermissions.viewOnlyIsUnconfirmed = true

        ClassroomPermissions.shareIsViewOnly = false

        #expect(!ClassroomPermissions.viewOnlyIsUnconfirmed)
        #expect(UserDefaults.standard.object(forKey: ClassroomPermissions.oldViewOnlyKey) == nil)
        #expect(UserDefaults.standard.object(forKey: ClassroomPermissions.viewOnlyKey) == nil)
    }

    private static func makeDefaults() -> UserDefaults {
        let name = "Fix1106ViewOnlyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// The app's own View only state and its two keys, put back after a test.
@MainActor
private struct SavedViewOnly {
    let viewOnly = ClassroomPermissions.shareIsViewOnly
    let unconfirmed = ClassroomPermissions.viewOnlyIsUnconfirmed
    let newKey = UserDefaults.standard.object(forKey: ClassroomPermissions.viewOnlyKey)
    let oldKey = UserDefaults.standard.object(forKey: ClassroomPermissions.oldViewOnlyKey)

    func restore() {
        ClassroomPermissions.shareIsViewOnly = viewOnly
        ClassroomPermissions.viewOnlyIsUnconfirmed = unconfirmed
        UserDefaults.standard.set(newKey, forKey: ClassroomPermissions.viewOnlyKey)
        UserDefaults.standard.set(oldKey, forKey: ClassroomPermissions.oldViewOnlyKey)
    }
}
