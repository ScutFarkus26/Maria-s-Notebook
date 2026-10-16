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

    private var reader: Task<Void, Never>?
    private var pendingRetry: Task<Void, Never>?
    private let settle: Duration
    private let retry: @MainActor () -> Void

    /// Follows `paths`, calling `retry` once a change has settled for
    /// `settle`. Tests pass their own paths and settle.
    init(
        paths: AsyncStream<PathState>,
        settle: Duration = AssistantNetworkWatch.settle,
        retry: @escaping @MainActor () -> Void
    ) {
        self.settle = settle
        self.retry = retry
        reader = Task { [weak self] in
            var last: PathState?
            for await path in paths {
                guard let self else { return }
                follow(path, after: last)
                last = path
            }
        }
    }

    /// The system's paths, from a fresh `NWPathMonitor`.
    static func live(retry: @escaping @MainActor () -> Void) -> AssistantNetworkWatch {
        AssistantNetworkWatch(paths: systemPaths(), retry: retry)
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
            // Gone again before the link settled: nothing to try on.
            pendingRetry?.cancel()
            pendingRetry = nil
            return
        }
        guard Self.shouldRetry(from: last, to: path) else { return }
        // Changes within the settle time make one retry, after the last.
        pendingRetry?.cancel()
        pendingRetry = Task { [weak self, settle] in
            do { try await Task.sleep(for: settle) } catch { return }
            guard let self, !Task.isCancelled else { return }
            Self.logger.notice("The network came back or changed: waiting marks are tried")
            pendingRetry = nil
            retry()
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
