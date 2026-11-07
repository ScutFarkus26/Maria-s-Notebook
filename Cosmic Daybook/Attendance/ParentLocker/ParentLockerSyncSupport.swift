import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

// The pieces `ParentLockerSync` is handed rather than reaching for, so its
// tests run instantly and never touch the network, the Keychain, the clock
// or the app's preferences: the clock, where the sign-in is kept, the list of
// changes not sent yet, and the iPhone's background-task window.

// MARK: - Everything handed

extension ParentLockerSync {
    /// Signs in through the site's own form and returns the cookies it set.
    typealias SignIn = @MainActor (ParentLockerKeychain.Credential, _ site: String) async throws -> [ParentLockerCookie]
    /// Makes the transport for `site` with `cookies`; `cookiesChanged` hears each change.
    typealias MakeTransport = @MainActor (
        _ site: String, _ cookies: [ParentLockerCookie],
        _ cookiesChanged: @escaping @Sendable ([ParentLockerCookie]) -> Void
    ) -> any ParentLockerTransport

    /// Everything the sync is handed rather than reaching for.
    struct Dependencies {
        var store: any ParentLockerStore
        var secrets: any ParentLockerSecrets = ParentLockerKeychainSecrets()
        var makeTransport: MakeTransport = ParentLockerSync.siteTransports()
        var signIn: SignIn = { credential, site in
            try await ParentLockerSignIn(site: site).run(credential, showsPagesWhenAsked: false)
        }
        var clock: any ParentLockerClock = ParentLockerSystemClock()
        var policy: ParentLockerSavePolicy = .current
        var unsent: any ParentLockerUnsentStore = ParentLockerSync.defaultUnsentStore()
        /// The saved password ParentLocker refused, remembered across launches
        /// in a build that saves.
        var refusals: any ParentLockerRefusalStore = ParentLockerSavePolicy.current.allowsSaving
            ? ParentLockerDefaultsRefusalStore() : ParentLockerMemoryRefusalStore()
        var background: any ParentLockerBackgroundWork = ParentLockerSystemBackgroundWork()
        var isInForeground: @MainActor () -> Bool = { ParentLockerAppState.isInForeground() }
        /// Whether CloudKit imports will come: false for a stack without
        /// CloudKit, where the catch-up needn't wait for one.
        var importsExpected = true
        /// Whether becoming active counts as a return only after
        /// `returnAbsence` away: on the Mac, which becomes active at every
        /// switch between apps.
        #if os(macOS)
        var returnNeedsAbsence = true
        #else
        var returnNeedsAbsence = false
        #endif
        var calendar: Calendar = AppCalendar.shared
    }
}

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
/// send them. Only child ids, ParentLocker's mark ids and the app's own
/// notes: never names, anyone else's words or anything of the sign-in.
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
    /// The whole-class send's kind (`ParentLockerWholeClass.Reason`'s raw
    /// value: "closeArrival", "sendNow" or "owed"), so it comes back as
    /// itself (bug hunt 2026-11-05 #2, #16). Builds before then saved none:
    /// arrival closed here reads as a Close Arrival & Send, as it did.
    var reason: String?
    /// What today's saves sent, by child and `course_id`, not yet read back
    /// (`ParentLockerSync.sending`): a relaunch knows a save whose reply was
    /// lost for its own (review of the 2026-11-05 fixes, E5).
    var sent: [UUID: [Int: ParentLockerSentRow]] = [:]
    /// The notes this device wrote in each child's Notes box today, by
    /// `course_id` (`ParentLockerSync.ownNotes`, W3). Builds before then
    /// saved neither: both read as empty.
    var notes: [UUID: [Int: Set<String>]] = [:]
    /// A class of the whole-class send owed has already gone
    /// (`ParentLockerSync.closeArrivalBatchSent`), so after a relaunch Siri's
    /// Undo of a half-sent Close Arrival still says some absences may be in
    /// ParentLocker (bug hunt 2026-11-06, #4). Builds before then saved
    /// none: it reads as false, as it did.
    var batchSent = false

    init(
        day: String, children: Set<UUID>, wholeClass: Bool, arrivalClosed: Bool = false, reason: String? = nil,
        sent: [UUID: [Int: ParentLockerSentRow]] = [:], notes: [UUID: [Int: Set<String>]] = [:],
        batchSent: Bool = false
    ) {
        self.day = day
        self.children = children
        self.wholeClass = wholeClass
        self.arrivalClosed = arrivalClosed
        self.reason = reason
        self.sent = sent
        self.notes = notes
        self.batchSent = batchSent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        children = try container.decode(Set<UUID>.self, forKey: .children)
        wholeClass = try container.decode(Bool.self, forKey: .wholeClass)
        arrivalClosed = try container.decodeIfPresent(Bool.self, forKey: .arrivalClosed) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        sent = try container.decodeIfPresent([UUID: [Int: ParentLockerSentRow]].self, forKey: .sent) ?? [:]
        notes = try container.decodeIfPresent([UUID: [Int: Set<String>]].self, forKey: .notes) ?? [:]
        batchSent = try container.decodeIfPresent(Bool.self, forKey: .batchSent) ?? false
    }

    var isEmpty: Bool { children.isEmpty && !wholeClass && !arrivalClosed && sent.isEmpty && notes.isEmpty }
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

/// What's owed, where it's kept, and Siri's Close Arrival with the sync not running.
extension ParentLockerSync {
    /// Where what's owed is kept: the app's preferences in a build that
    /// saves, memory otherwise (`ParentLockerDefaultsUnsentStore`).
    nonisolated static func defaultUnsentStore() -> any ParentLockerUnsentStore {
        ParentLockerSavePolicy.current.allowsSaving
            ? ParentLockerDefaultsUnsentStore() : ParentLockerMemoryUnsentStore()
    }

    /// Close Arrival & Send made while the class's sync isn't running (Siri,
    /// with the app launched for the intent alone): the whole-class send is
    /// kept owed for `day`, with arrival closed, and the sync sends it when
    /// it starts and is signed in.
    nonisolated static func oweCloseArrivalSend(on day: Date, in unsent: any ParentLockerUnsentStore) {
        let id = AppCalendar.dayID(day)
        var owed = unsent.load().flatMap { $0.day == id ? $0 : nil }
            ?? ParentLockerUnsent(day: id, children: [], wholeClass: false)
        owed.wholeClass = true
        owed.arrivalClosed = true
        owed.reason = ParentLockerWholeClass.Reason.closeArrival.rawValue
        unsent.save(owed)
    }

    /// Siri's undo of a Close Arrival made while the class's sync isn't
    /// running: the whole-class send kept owed for `day`, and its "arrival
    /// closed", are taken back, so a later sign-in never sends a reopened
    /// class (bug hunt 2026-10-13 afternoon, H2).
    nonisolated static func cancelOwedCloseArrivalSend(on day: Date, in unsent: any ParentLockerUnsentStore) {
        guard var owed = unsent.load(), owed.day == AppCalendar.dayID(day) else { return }
        owed.wholeClass = false
        owed.arrivalClosed = false
        owed.reason = nil
        unsent.save(owed.isEmpty ? nil : owed)
    }
}

// MARK: - Sign-outs

/// Counts sign-outs, from any thread: a reply that lands after one keeps
/// none of the cookies it brings, so a session ParentLocker set before the
/// sign-out doesn't come back (bug hunt 2026-11-05 #25).
nonisolated final class ParentLockerSignOuts: Sendable {
    private let count = Mutex(0)

    var current: Int { count.withLock { $0 } }

    /// Runs `body` (a save of cookies) only while no sign-out has come since
    /// `generation`, under the same lock as `signOut`.
    func ifNoneSince(_ generation: Int, _ body: () -> Void) {
        count.withLock { if $0 == generation { body() } }
    }

    /// A sign-out: `body` (the cookies' delete) runs under the lock, so no
    /// save slips in between.
    func signOut(_ body: () -> Void) {
        count.withLock {
            $0 += 1
            body()
        }
    }
}

// MARK: - A refused password

/// The saved password ParentLocker refused, by when it was saved (the
/// Keychain item's modification date): until a new one is saved, here or on
/// another of the person's devices, the sync doesn't sign in with it by
/// itself, so the school's site doesn't see a wrong password again and again.
nonisolated protocol ParentLockerRefusalStore: Sendable {
    /// When the refused password was saved; nil when none was refused.
    func refused(site: String) -> Date?
    /// Remembers `saved` as refused; nil forgets.
    func setRefused(_ saved: Date?, site: String)
}

/// In the app's preferences, so a relaunch doesn't try it again: a date per
/// site, nothing of the sign-in. Only a `.live` build keeps one.
nonisolated struct ParentLockerDefaultsRefusalStore: ParentLockerRefusalStore {
    static let key = "ParentLocker.refusedPassword"

    func refused(site: String) -> Date? {
        UserDefaults.standard.dictionary(forKey: Self.key)?[site] as? Date
    }

    func setRefused(_ saved: Date?, site: String) {
        var refused = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
        guard (refused[site] as? Date) != saved else { return }
        refused[site] = saved
        if refused.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set(refused, forKey: Self.key)
        }
    }
}

/// In memory only: previews, and tests.
nonisolated final class ParentLockerMemoryRefusalStore: ParentLockerRefusalStore {
    private let stored = Mutex<[String: Date]>([:])

    func refused(site: String) -> Date? { stored.withLock { $0[site] } }

    func setRefused(_ saved: Date?, site: String) { stored.withLock { $0[site] = saved } }
}

// MARK: - Background

/// Keeps the app running while a send is under way or due within seconds,
/// so a phone locked right after Close Arrival still sends (Apple guidance,
/// item 5). On the Mac, and in tests, it does nothing.
@MainActor
protocol ParentLockerBackgroundWork: AnyObject {
    /// A window is held: begun, and neither ended nor ended by iOS (time's
    /// up), and not refused when asked for.
    var isHeld: Bool { get }
    func begin()
    func end()
}

/// `beginBackgroundTask` on iPhone and iPad; nothing on the Mac.
@MainActor
final class ParentLockerSystemBackgroundWork: ParentLockerBackgroundWork {
    #if canImport(UIKit) && !os(watchOS)
    /// The window's identifier, shared with its expiration handler, which
    /// ends it even when this object (and its sync) has gone.
    private let window = Window()

    /// iOS refuses a window (`.invalid`) when the app can't run in the
    /// background, and ends one whose time is up: neither holds one, so the
    /// next send asks again (bug hunt 2026-11-05 #21).
    var isHeld: Bool { window.id != .invalid }

    func begin() {
        guard window.id == .invalid else { return }
        let window = window
        window.id = UIApplication.shared.beginBackgroundTask(withName: "Send attendance to ParentLocker") {
            // Time's up: the system suspends the app, and the catch-up on the
            // way back sends what's still owed.
            MainActor.assumeIsolated { window.end() }
        }
    }

    func end() { window.end() }

    /// A sync let go without `stop()` takes its window with it.
    deinit {
        let window = window
        Task { @MainActor in window.end() }
    }

    @MainActor
    private final class Window {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
    #else
    private(set) var isHeld = false
    func begin() { isHeld = true }
    func end() { isHeld = false }
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
