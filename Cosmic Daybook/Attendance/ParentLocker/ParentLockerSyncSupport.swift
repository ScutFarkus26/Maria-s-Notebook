import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

// The pieces `ParentLockerSync` is handed rather than reaching for, so its
// tests run instantly and never touch the network, the Keychain, the clock
// or the app's preferences: the clock, where the sign-in is kept, the list of
// changes not sent yet, and the iPhone's background-task window.

// MARK: - Clock

/// What time it is, and a way to wait until a moment. Every wait the sync
/// makes goes through one, so a test moves time by hand.
nonisolated protocol ParentLockerClock: Sendable {
    var now: Date { get }
    /// Returns at `deadline`, or throws when the waiting task is cancelled.
    func sleep(until deadline: Date) async throws
}

/// The real clock. A second of slack lets the system batch the wake with others.
nonisolated struct ParentLockerSystemClock: ParentLockerClock {
    var now: Date { Date() }

    func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSinceNow
        guard seconds > 0 else { return try Task.checkCancellation() }
        try await Task.sleep(for: .seconds(seconds), tolerance: .seconds(1))
    }
}

// MARK: - Sign-in

/// Where the sign-in is kept: `ParentLockerKeychain` in the apps, a fake in
/// the tests. Safe to call from any thread.
nonisolated protocol ParentLockerSecrets: Sendable {
    func credential(site: String) throws -> ParentLockerKeychain.Credential?
    func hasPassword(site: String) throws -> Bool
    /// When the password was last saved, here or on another of the person's
    /// devices; nil when there is none (`ParentLockerKeychain.passwordModified`).
    func passwordModified(site: String) throws -> Date?
    func savePassword(_ credential: ParentLockerKeychain.Credential, site: String) throws
    func deletePassword(site: String) throws
    func cookies(site: String) throws -> [ParentLockerCookie]
    func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws
    func deleteCookies(site: String) throws
}

/// The Keychain items `ParentLockerKeychain` keeps.
nonisolated struct ParentLockerKeychainSecrets: ParentLockerSecrets {
    func credential(site: String) throws -> ParentLockerKeychain.Credential? {
        try ParentLockerKeychain.credential(site: site)
    }
    func hasPassword(site: String) throws -> Bool { try ParentLockerKeychain.hasPassword(site: site) }
    func passwordModified(site: String) throws -> Date? { try ParentLockerKeychain.passwordModified(site: site) }
    func savePassword(_ credential: ParentLockerKeychain.Credential, site: String) throws {
        try ParentLockerKeychain.savePassword(credential, site: site)
    }
    func deletePassword(site: String) throws { try ParentLockerKeychain.deletePassword(site: site) }
    func cookies(site: String) throws -> [ParentLockerCookie] { try ParentLockerKeychain.cookies(site: site) }
    func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws {
        try ParentLockerKeychain.saveCookies(cookies, site: site)
    }
    func deleteCookies(site: String) throws { try ParentLockerKeychain.deleteCookies(site: site) }
}

// MARK: - Changes not sent yet

/// The children whose marks this device changed and ParentLocker hasn't got
/// yet, whether the day's whole-class send is still owed, and whether arrival
/// closed here. Kept across launches so the catch-up on the way back can
/// send them; only child ids, never names, marks or anything of the sign-in.
nonisolated struct ParentLockerUnsent: Codable, Equatable, Sendable {
    /// The day it's for (`AppCalendar.dayID`); another day's is dropped.
    var day: String
    var children: Set<UUID>
    var wholeClass: Bool
    /// Close Arrival & Send was made here, or a whole-class send started: the
    /// day is past "after" on this device whatever its automatic absences say
    /// now (a child marked Late in the Undo window takes the last one away).
    /// Only that Close Arrival's Undo clears it. Builds before the 2026-10-13
    /// fixes saved no such field, which reads as false.
    var arrivalClosed: Bool

    init(day: String, children: Set<UUID>, wholeClass: Bool, arrivalClosed: Bool = false) {
        self.day = day
        self.children = children
        self.wholeClass = wholeClass
        self.arrivalClosed = arrivalClosed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        children = try container.decode(Set<UUID>.self, forKey: .children)
        wholeClass = try container.decode(Bool.self, forKey: .wholeClass)
        arrivalClosed = try container.decodeIfPresent(Bool.self, forKey: .arrivalClosed) ?? false
    }

    var isEmpty: Bool { children.isEmpty && !wholeClass && !arrivalClosed }
}

/// Where `ParentLockerUnsent` is kept.
nonisolated protocol ParentLockerUnsentStore: Sendable {
    func load() -> ParentLockerUnsent?
    /// Saves it; nil or an empty one removes it.
    func save(_ unsent: ParentLockerUnsent?)
}

/// In the app's preferences. Only a `.live` build keeps one: a Debug copy
/// shares the Release copy's preferences on the Mac, and its previews must
/// not clear what the Release copy still owes.
nonisolated struct ParentLockerDefaultsUnsentStore: ParentLockerUnsentStore {
    static let key = "ParentLocker.unsentChanges"

    func load() -> ParentLockerUnsent? {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(ParentLockerUnsent.self, from: data)
    }

    func save(_ unsent: ParentLockerUnsent?) {
        guard let unsent, !unsent.isEmpty, let data = try? JSONEncoder().encode(unsent) else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// In memory only: previews, and tests.
nonisolated final class ParentLockerMemoryUnsentStore: ParentLockerUnsentStore {
    private let stored: Mutex<ParentLockerUnsent?>

    init(_ unsent: ParentLockerUnsent? = nil) { stored = Mutex(unsent) }

    func load() -> ParentLockerUnsent? { stored.withLock { $0 } }

    func save(_ unsent: ParentLockerUnsent?) {
        stored.withLock { $0 = unsent?.isEmpty == false ? unsent : nil }
    }
}

// MARK: - Background

/// Keeps the app running while a send is under way or due within seconds,
/// so a phone locked right after Close Arrival still sends (Apple guidance,
/// item 5). On the Mac, and in tests, it does nothing.
@MainActor
protocol ParentLockerBackgroundWork: AnyObject {
    func begin()
    func end()
}

/// `beginBackgroundTask` on iPhone and iPad; nothing on the Mac.
@MainActor
final class ParentLockerSystemBackgroundWork: ParentLockerBackgroundWork {
    #if canImport(UIKit) && !os(watchOS)
    private var task: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "Send attendance to ParentLocker") { [weak self] in
            // Time's up: the system suspends the app, and the catch-up on the
            // way back sends what's still owed.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
    #else
    func begin() {}
    func end() {}
    #endif
}

/// Whether the app is in front: signing back in needs the web view, which
/// stalls in the background, so only a sync in front tries.
@MainActor
enum ParentLockerAppState {
    static func isInForeground() -> Bool {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.applicationState != .background
        #else
        true
        #endif
    }
}
