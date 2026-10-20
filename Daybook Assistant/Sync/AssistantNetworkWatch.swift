import Foundation
import Network
import OSLog

/// Tries the waiting marks again when the network comes back or changes.
///
/// Her marks go into the classroom share only while the app runs, and a pass
/// that couldn't reach iCloud rests before its next try. Nothing noticed the
/// network returning: Wi-Fi dropped on the way out to the car line, the marks
/// failed, and when the phone rejoined Wi-Fi or moved to cellular they waited
/// out the rest, or until she tapped again or reopened the app. Now a path
/// that becomes usable, or moves between Wi-Fi and cellular, tries what waits
/// once the link has settled.
///
/// A trigger, never a gate: a mark is tried after every save whatever the
/// path says, since a path can claim to be online when it isn't, and the
/// other way round. A wrong answer here costs at most one extra try.
///
/// The network coming back (from none, not a move between Wi-Fi and
/// cellular) also runs the ParentLocker sync's return path, as coming back
/// to the app does (bug hunt 2026-10-20, #16): a send that gave up while the
/// phone was offline waited for the next trip away and back. Only a return,
/// so a link flapping between kinds doesn't keep restarting the sync's wait
/// for the first import; and not while that wait runs, or just after the app
/// came back, whose own return has run it (`runsParentLockerReturn`).
///
/// One per stack (`AssistantStack`), stopped when a rebuild closes it.
@MainActor
final class AssistantNetworkWatch {
    private static let logger = Logger.app(category: "networkWatch")

    /// The kind of link a path runs over.
    nonisolated enum Interface: Sendable, Equatable {
        case wifi, cellular, wired, other
    }

    /// What the watch needs of a network path.
    nonisolated struct PathState: Sendable, Equatable {
        var usable: Bool
        var interface: Interface

        init(usable: Bool, interface: Interface) {
            self.usable = usable
            self.interface = interface
        }

        init(_ path: NWPath) {
            usable = path.status == .satisfied
            interface = if path.usesInterfaceType(.wifi) {
                .wifi
            } else if path.usesInterfaceType(.cellular) {
                .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                .wired
            } else {
                .other
            }
        }
    }

    /// How long a new link settles before the retry: a phone joining Wi-Fi
    /// reports a path before traffic flows on it.
    static let settle: Duration = .seconds(3)

    /// Whether moving from `old` to `new` should try the waiting marks: the
    /// network came back, or moved to another kind of link. The first path
    /// (`old` nil) only sets the scene: the launch already tries them.
    nonisolated static func shouldRetry(from old: PathState?, to new: PathState) -> Bool {
        guard let old, new.usable else { return false }
        return !old.usable || old.interface != new.interface
    }

    /// Whether moving from `old` to `new` is the network coming back: from
    /// no usable path to one. The first path only sets the scene.
    nonisolated static func cameBack(from old: PathState?, to new: PathState) -> Bool {
        guard let old else { return false }
        return !old.usable && new.usable
    }

    /// How soon after the app became active the network's return counts as
    /// part of that return: a phone rejoins Wi-Fi as it wakes, and `settle`
    /// adds its few seconds.
    nonisolated static let returnOverlap: TimeInterval = 10

    /// Whether the network's return runs ParentLocker's return path. Not
    /// while the sync still waits for its first import (a return to the app
    /// started that wait, and the import comes with the network), and not
    /// within `returnOverlap` of the app becoming active, whose own return
    /// ran it seconds before: the two together restarted the wait (review of
    /// the 2026-10-20 fixes). `activeSince` is nil while the app isn't
    /// active. Pure, for the tests.
    nonisolated static func runsParentLockerReturn(awaitingImport: Bool, activeSince: Date?, now: Date) -> Bool {
        guard !awaitingImport else { return false }
        guard let activeSince else { return true }
        return now.timeIntervalSince(activeSince) >= returnOverlap
    }

    private var reader: Task<Void, Never>?
    private var pendingRetry: Task<Void, Never>?
    /// A change waiting to settle came back from no network.
    private var pendingCameBack = false
    private let settle: Duration
    private let retry: @MainActor () -> Void
    private let cameBack: @MainActor () -> Void

    /// Follows `paths`, calling `retry` once a change has settled for
    /// `settle`, and `cameBack` too when the change was the network coming
    /// back. Tests pass their own paths and settle.
    init(
        paths: AsyncStream<PathState>,
        settle: Duration = AssistantNetworkWatch.settle,
        retry: @escaping @MainActor () -> Void,
        cameBack: @escaping @MainActor () -> Void = {}
    ) {
        self.settle = settle
        self.retry = retry
        self.cameBack = cameBack
        reader = Task { [weak self] in
            var last: PathState?
            for await path in paths {
                guard let self else { return }
                follow(path, after: last)
                last = path
            }
        }
    }

    /// The system's paths, from a fresh `NWPathMonitor`. The network coming
    /// back reaches the class's ParentLocker sync, when one is running and
    /// hasn't just run its return (`runsParentLockerReturn`).
    static func live(retry: @escaping @MainActor () -> Void) -> AssistantNetworkWatch {
        AssistantNetworkWatch(paths: systemPaths(), retry: retry) {
            guard let sync = ParentLockerSync.current, runsParentLockerReturn(
                awaitingImport: sync.awaitingImport, activeSince: ArrivalReminderTaps.activeSince, now: Date()
            ) else { return }
            sync.appReturned()
        }
    }

    /// Ends the watch: no retry starts after this.
    func stop() {
        reader?.cancel()
        reader = nil
        pendingRetry?.cancel()
        pendingRetry = nil
    }

    deinit {
        reader?.cancel()
        pendingRetry?.cancel()
    }

    private func follow(_ path: PathState, after last: PathState?) {
        if !path.usable {
            // Gone again before the link settled: nothing to try on. The
            // next usable path is a return of its own.
            pendingRetry?.cancel()
            pendingRetry = nil
            pendingCameBack = false
            return
        }
        guard Self.shouldRetry(from: last, to: path) else { return }
        // Changes within the settle time make one retry, after the last;
        // a return among them reaches ParentLocker once too.
        if Self.cameBack(from: last, to: path) { pendingCameBack = true }
        pendingRetry?.cancel()
        pendingRetry = Task { [weak self, settle] in
            do { try await Task.sleep(for: settle) } catch { return }
            guard let self, !Task.isCancelled else { return }
            Self.logger.notice("The network came back or changed: waiting marks are tried")
            pendingRetry = nil
            let returned = pendingCameBack
            pendingCameBack = false
            retry()
            if returned { cameBack() }
        }
    }

    /// `NWPathMonitor`'s paths as `PathState`s. Its iterator isn't
    /// `Sendable`, so one task reads it; ending the stream cancels the
    /// monitor.
    private static func systemPaths() -> AsyncStream<PathState> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let task = Task.detached {
                for await path in monitor { continuation.yield(PathState(path)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                monitor.cancel()
            }
        }
    }
}
