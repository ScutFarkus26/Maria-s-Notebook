// UbiquityContainerCache.swift
// The app's iCloud container URL, looked up off the main thread and kept
// until the iCloud identity changes.

import Foundation
import Synchronization

/// The app's iCloud ubiquity container, looked up once and kept until the
/// iCloud identity changes.
///
/// Apple's documentation for `FileManager.url(forUbiquityContainerIdentifier:)`
/// says not to call it from the main thread, because it "might take a
/// nontrivial amount of time to set up iCloud". The managed document folders
/// (`ManagedPDFFileStorage.directory()`) called it on every use, and most uses
/// run on the main thread: the relative-path fallback of a stored file's
/// resolution, every `resolve(relativePath:)`, imports and deletes.
///
/// This keeps the answer. `startRefreshing()` looks it up off the main thread
/// at launch, where `AppBootstrapper` already asked in order to activate the
/// container, and again whenever `NSUbiquityIdentityDidChange` is posted. A
/// read returns the kept answer while it was looked up under the current
/// `ubiquityIdentityToken`, which Apple documents as fast enough for the main
/// thread and which changes when the user signs in or out, switches accounts
/// or turns iCloud Drive off. So each of those takes effect on the next read,
/// as it did when every read asked FileManager. A read with nothing kept for
/// the current identity asks on the calling thread, as every read used to,
/// and keeps the answer.
///
/// "iCloud unavailable" is kept like any other answer: nil for as long as
/// there is no identity, and the folders fall back to local Documents exactly
/// as before. A nil answer while there *is* an identity (a container not set
/// up yet) is not kept, so the next read asks again.
nonisolated final class UbiquityContainerCache: Sendable {

    static let shared = UbiquityContainerCache()

    /// The two FileManager calls, replaceable in tests.
    struct System: Sendable {
        /// The current `ubiquityIdentityToken`'s hash, nil when iCloud is
        /// unavailable. Equal tokens hash equally, so a new hash is a new
        /// identity.
        let identity: @Sendable () -> Int?
        /// `url(forUbiquityContainerIdentifier: nil)`: the app's container.
        let containerURL: @Sendable () -> URL?

        static let live = System(
            identity: { FileManager.default.ubiquityIdentityToken?.hash },
            containerURL: { FileManager.default.url(forUbiquityContainerIdentifier: nil) }
        )
    }

    /// An answer, and the identity it was looked up under.
    private struct Answer: Sendable {
        let identity: Int?
        let url: URL?
    }

    private let system: System
    private let kept = Mutex<Answer?>(nil)
    private let lookups = Mutex(0)
    private let started = Mutex(false)

    init(system: System = .live) {
        self.system = system
    }

    /// How many times this cache has asked FileManager (for tests).
    var lookupCount: Int {
        lookups.withLock { $0 }
    }

    /// The container's URL, or nil when iCloud is unavailable.
    func url() -> URL? {
        let identity = system.identity()
        if let answer = kept.withLock({ $0 }), answer.identity == identity {
            return answer.url
        }
        return lookUp()
    }

    /// Asks FileManager on the calling thread and keeps the answer, unless
    /// the identity changed while it asked, or the container is missing
    /// while iCloud has an identity.
    @discardableResult
    func lookUp() -> URL? {
        let before = system.identity()
        let url = system.containerURL()
        lookups.withLock { $0 += 1 }
        let after = system.identity()
        if before == after, url != nil || after == nil {
            kept.withLock { $0 = Answer(identity: after, url: url) }
        }
        return url
    }

    /// Asks FileManager off the main thread and keeps the answer.
    @concurrent
    func refresh() async {
        lookUp()
    }

    /// Looks the container up off the main thread now, and again whenever
    /// the iCloud identity changes. Once per cache; later calls do nothing.
    func startRefreshing(center: NotificationCenter = .default) {
        let first = started.withLock { started in
            defer { started = true }
            return !started
        }
        guard first else { return }
        // `.utility`, as the launch warm-up this replaces ran: off the main
        // thread, `.background` work can wait tens of seconds for a core.
        _ = center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil) { [self] _ in
            Task(priority: .utility) { await self.refresh() }
        }
        Task(priority: .utility) { await refresh() }
    }
}
