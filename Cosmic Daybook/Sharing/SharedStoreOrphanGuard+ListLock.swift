import Foundation
import OSLog
import Synchronization

// MARK: - One copy at a time on the waiting list
//
// The Mac can run more than one copy of the app at once (the installed app, a
// Debug build, a copy the MCP bridge launched), and every copy reads and
// rewrites the same waiting list in UserDefaults: a second copy only lists
// what it makes, and the first attaches it. Each change reads the list,
// changes it and writes it back, so an entry one copy added between another
// copy's read and its write was lost when that write landed: a pass in the
// first copy forgetting what it had attached wrote back the list as it had
// read it (bug hunt 2026-11-02, #35). Every change to the list now takes a
// file lock that only one copy holds at a time, and reads the list inside it.

extension SharedStoreOrphanGuard {

    /// The lock file every copy of the app takes to change the waiting list,
    /// held for one read, change and write.
    ///
    /// `flock` locks belong to an open file, not a process, so two of these on
    /// one folder exclude each other as two copies of the app would; the tests
    /// rely on that. Within one copy the main actor keeps changes one at a
    /// time. Not reentrant: a change never makes another inside it. It fails
    /// open: a lock file that can't be opened, or another copy holding it past
    /// `patience` (stopped in the debugger, say), lets the change go ahead
    /// unlocked, as before the lock existed, rather than hang the main thread.
    nonisolated final class ListLock: Sendable {
        static let fileName = ".classroom-waiting-list.lock"
        private static let logger = Logger.sharedStoreOrphanGuard

        let url: URL
        let patience: Duration
        /// The open lock file: nil until first used, -1 once it couldn't be opened.
        private let descriptor = Mutex<Int32?>(nil)

        init(directory: URL, patience: Duration = .seconds(1)) {
            url = directory.appendingPathComponent(Self.fileName)
            self.patience = patience
        }

        deinit {
            descriptor.withLock { fd in
                if let existing = fd, existing >= 0 { Darwin.close(existing) }
            }
        }

        /// Runs `change` holding the lock (failing open, without it).
        func withLock<T>(_ change: () throws -> T) rethrows -> T {
            let fd = openFile()
            let held = fd >= 0 && take(fd)
            defer { if held { flock(fd, LOCK_UN) } }
            return try change()
        }

        private func openFile() -> Int32 {
            descriptor.withLock { fd in
                if let existing = fd { return existing }
                let opened = open(url.path, O_RDWR | O_CREAT, 0o644)
                if opened < 0 {
                    let code = errno
                    Self.logger.error("Waiting-list lock file couldn't be opened (errno \(code, privacy: .public))")
                }
                fd = opened
                return opened
            }
        }

        /// Waits up to `patience` for another copy to finish its change.
        private func take(_ fd: Int32) -> Bool {
            let deadline = ContinuousClock.now.advanced(by: patience)
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                let code = errno
                guard code == EWOULDBLOCK || code == EINTR else {
                    Self.logger.error("Waiting-list lock refused (errno \(code, privacy: .public)); changing unlocked")
                    return false
                }
                guard ContinuousClock.now < deadline else {
                    Self.logger.error("Another copy held the waiting list too long; changing it unlocked")
                    return false
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            return true
        }
    }
}
