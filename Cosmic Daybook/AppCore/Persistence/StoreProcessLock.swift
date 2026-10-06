import Foundation
import OSLog
import Synchronization

/// Which running copy of the app may change the store files outside Core Data.
///
/// On the Mac more than one copy can have the notebook open at once: the
/// installed app, a Debug build from Xcode, a copy the MCP bridge launched.
/// Each used to run the launch's store surgery on its own (the pre-migration
/// backup and its restore, the orphan-metadata cleanup, the stale-key repair,
/// the schema stamp, the Re-download reset) while the others had the same
/// files open. Editing a SQLite file under another process's connection is how
/// a store gets corrupted, and a migration run under another copy is how the
/// 2026-08-25 downgrade dropped tables from a store two newer copies held.
///
/// So every copy that opens the stores holds a *shared* lock for as long as it
/// runs, and surgery needs the lock *exclusively*, which only a copy with the
/// stores to itself can get. The first copy to open the stores takes it at
/// launch and is the primary (`CoreDataStack.isPrimaryProcess`): only it runs
/// launch repairs and duplicate cleanup. A later copy opens the stores without
/// surgery, and refuses to open them at all when surgery is due (a migration,
/// an armed Re-download), saying to close the other copy.
///
/// Two lock files, because `flock` can't change a lock's kind in one step:
/// turning exclusive into shared releases the lock first, and another copy
/// could take it exclusively in between. The surgery file is the gate: only
/// its holder may ask for the presence file exclusively, or give that up, so
/// no copy ever sees the gap. `flock` locks belong to an open file, not a
/// process, so two of these on one folder exclude each other as two copies of
/// the app would; the tests rely on that.
nonisolated final class StoreProcessLock: Sendable {
    private static let logger = Logger.app(category: "StoreLock")

    /// Held shared by every copy for its life; exclusively for surgery.
    static let presenceFileName = ".store-presence.lock"
    /// Held by whoever is deciding about, or holding, the exclusive lock.
    static let surgeryFileName = ".store-surgery.lock"

    private struct State {
        var presence: Int32 = -1
        var surgery: Int32 = -1
        var holdsShared = false
        var holdsExclusive = false
        /// Set by the first `tryExclusive()`: whether this copy had the stores to itself at launch.
        var primary: Bool?
        /// The lock files couldn't be opened: nothing can be coordinated, so
        /// everything is allowed, as before the lock existed.
        var unavailable = false
    }

    let directory: URL
    private let state = Mutex(State())

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        close()
    }

    /// Whether this copy took the stores exclusively the first time it asked
    /// (at launch). False until it has asked.
    var isPrimary: Bool {
        state.withLock { $0.primary == true }
    }

    /// Whether this copy found another copy holding the stores when it opened
    /// them. False until the stores are opened, and for a process that has
    /// opened none on disk (tests, in-memory stacks): unlike `!isPrimary`.
    var isSecondary: Bool {
        state.withLock { $0.primary == false }
    }

    /// Whether this copy holds the stores for surgery right now.
    var holdsExclusive: Bool {
        state.withLock { $0.holdsExclusive }
    }

    /// Takes the stores for surgery: true when no other copy has them open.
    /// Holding them already counts. When another copy has them, this copy
    /// keeps (or takes) its shared hold and gets false. The first call
    /// decides `isPrimary`.
    func tryExclusive() -> Bool {
        state.withLock { lock in
            if lock.holdsExclusive { return true }
            guard Self.openFiles(&lock, in: directory) else {
                if lock.primary == nil { lock.primary = true }
                return true
            }
            // Another copy is deciding, or doing surgery, right now.
            guard flock(lock.surgery, LOCK_EX | LOCK_NB) == 0 else {
                if lock.primary == nil { lock.primary = false }
                return false
            }
            // From a shared hold this converts; a refusal leaves the shared hold in place.
            if flock(lock.presence, LOCK_EX | LOCK_NB) == 0 {
                lock.holdsExclusive = true
                lock.holdsShared = false
                if lock.primary == nil { lock.primary = true }
                return true
            }
            // Someone else is running. Holding the gate, nobody holds the
            // presence file exclusively, so the shared hold is free to take.
            if flock(lock.presence, LOCK_SH | LOCK_NB) == 0 { lock.holdsShared = true }
            flock(lock.surgery, LOCK_UN)
            if lock.primary == nil { lock.primary = false }
            return false
        }
    }

    /// Makes a second copy the primary once no other copy has the stores
    /// open: true when this copy is (now) the primary. Only one copy can win,
    /// since only one can take the stores exclusively, and while two or more
    /// remain neither does. False for a process that never opened stores.
    func promoteIfAlone() -> Bool {
        if isPrimary { return true }
        guard isSecondary, tryExclusive() else { return false }
        releaseExclusive()
        state.withLock { $0.primary = true }
        Self.logger.notice("No other copy has the notebook open now: this copy is the primary")
        return true
    }

    /// Ends surgery: back to the shared hold every running copy keeps.
    func releaseExclusive() {
        state.withLock { lock in
            guard lock.holdsExclusive else { return }
            // Still holding the gate, so no other copy can take the presence
            // file exclusively while this converts.
            if flock(lock.presence, LOCK_SH) == 0 { lock.holdsShared = true }
            flock(lock.surgery, LOCK_UN)
            lock.holdsExclusive = false
        }
    }

    /// Takes the shared hold, waiting up to `timeout` for a copy in the middle
    /// of surgery (a migration, say) to finish. False if it doesn't.
    func holdShared(timeout: Duration) -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            let taken: Bool = state.withLock { lock in
                if lock.holdsShared || lock.holdsExclusive { return true }
                guard Self.openFiles(&lock, in: directory) else { return true }
                guard flock(lock.presence, LOCK_SH | LOCK_NB) == 0 else { return false }
                lock.holdsShared = true
                return true
            }
            if taken { return true }
            guard ContinuousClock.now < deadline else {
                Self.logger.error("Another copy kept the notebook's store files for surgery; gave up waiting")
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Lets go of everything. The process ending does the same; tests call it.
    func close() {
        state.withLock { lock in
            for descriptor in [lock.presence, lock.surgery] where descriptor >= 0 {
                flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
            lock.presence = -1
            lock.surgery = -1
            lock.holdsShared = false
            lock.holdsExclusive = false
        }
    }

    // MARK: - Files

    private static func openFiles(_ lock: inout State, in directory: URL) -> Bool {
        if lock.unavailable { return false }
        if lock.presence >= 0, lock.surgery >= 0 { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.fault("Store lock folder unavailable: \(error.localizedDescription, privacy: .public)")
        }
        let presence = open(directory.appendingPathComponent(presenceFileName).path, O_RDWR | O_CREAT, 0o644)
        let surgery = open(directory.appendingPathComponent(surgeryFileName).path, O_RDWR | O_CREAT, 0o644)
        guard presence >= 0, surgery >= 0 else {
            let code = errno
            if presence >= 0 { Darwin.close(presence) }
            if surgery >= 0 { Darwin.close(surgery) }
            lock.unavailable = true
            // Fail open: refusing to open the notebook because a lock file
            // can't be made would be worse than the surgery it guards.
            logger.fault("Store lock files couldn't be opened (errno \(code, privacy: .public)); not coordinating")
            return false
        }
        lock.presence = presence
        lock.surgery = surgery
        return true
    }
}
