import Foundation
import OSLog
import Synchronization
import Testing
@testable import CosmicDaybook

/// An iCloud the test scripts: an identity and a container it changes at
/// will, counting the lookups made on the main thread.
private nonisolated final class ScriptedICloud: Sendable {
    struct State {
        var identity: Int?
        var container: URL?
        /// Switches the identity to `identityAfterLookup` inside the next lookup.
        var flipsDuringNextLookup = false
        var identityAfterLookup: Int?
        var mainThreadLookups = 0
    }

    let state: Mutex<State>

    init(identity: Int? = 1, container: URL? = URL(fileURLWithPath: "/Mobile Documents/iCloud~Test")) {
        state = Mutex(State(identity: identity, container: container))
    }

    var system: UbiquityContainerCache.System {
        UbiquityContainerCache.System(
            identity: { [self] in state.withLock { $0.identity } },
            containerURL: { [self] in
                state.withLock { current in
                    if Thread.isMainThread { current.mainThreadLookups += 1 }
                    if current.flipsDuringNextLookup {
                        current.flipsDuringNextLookup = false
                        current.identity = current.identityAfterLookup
                    }
                    return current.container
                }
            }
        )
    }

    func set(identity: Int?, container: URL?) {
        state.withLock {
            $0.identity = identity
            $0.container = container
        }
    }

    var mainThreadLookups: Int {
        state.withLock { $0.mainThreadLookups }
    }
}

/// The managed document folders read the iCloud container's URL from a cache
/// filled off the main thread, instead of asking FileManager on the main
/// thread every time. These pin that the cache answers what FileManager
/// answers: it asks again whenever the iCloud identity changes (sign in, sign
/// out, another account, iCloud Drive off), keeps "unavailable" as nil, never
/// keeps a missing container while there is an identity, and does its launch
/// and identity-change lookups off the main thread. And that `directory()`,
/// and a stored file's relative-path fallback, land where the old code
/// (kept verbatim below) put them.
@Suite("iCloud container cache")
@MainActor
struct UbiquityContainerCacheTests {

    /// Polls until `cache` has looked up `count` times, for up to ten seconds.
    private func waitForLookups(_ count: Int, in cache: UbiquityContainerCache) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while cache.lookupCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - The Cache

    @Test("Reads under one identity ask FileManager once and answer what it answered")
    func readsUnderOneIdentityAskOnce() {
        let icloud = ScriptedICloud()
        let cache = UbiquityContainerCache(system: icloud.system)
        for _ in 0..<100 {
            #expect(cache.url() == URL(fileURLWithPath: "/Mobile Documents/iCloud~Test"))
        }
        #expect(cache.lookupCount == 1)
    }

    @Test("Unavailable is kept as nil until there is an identity; each change asks again")
    func identityChangesAskAgain() {
        let icloud = ScriptedICloud(identity: nil, container: nil)
        let cache = UbiquityContainerCache(system: icloud.system)
        let container = URL(fileURLWithPath: "/Mobile Documents/iCloud~Test")

        // iCloud unavailable: nil, asked for once.
        for _ in 0..<10 { #expect(cache.url() == nil) }
        #expect(cache.lookupCount == 1)

        // Signing in.
        icloud.set(identity: 1, container: container)
        #expect(cache.url() == container)
        #expect(cache.url() == container)
        #expect(cache.lookupCount == 2)

        // Another account.
        icloud.set(identity: 2, container: container)
        #expect(cache.url() == container)
        #expect(cache.lookupCount == 3)

        // Signing out, or turning iCloud Drive off.
        icloud.set(identity: nil, container: nil)
        #expect(cache.url() == nil)
        #expect(cache.url() == nil)
        #expect(cache.lookupCount == 4)
    }

    @Test("A missing container while there is an identity is asked for again")
    func missingContainerIsNotKept() {
        let icloud = ScriptedICloud(identity: 1, container: nil)
        let cache = UbiquityContainerCache(system: icloud.system)
        #expect(cache.url() == nil)
        #expect(cache.url() == nil)
        #expect(cache.lookupCount == 2)

        let container = URL(fileURLWithPath: "/Mobile Documents/iCloud~Test")
        icloud.set(identity: 1, container: container)
        #expect(cache.url() == container)
        #expect(cache.url() == container)
        #expect(cache.lookupCount == 3)
    }

    @Test("An identity change during a lookup keeps nothing")
    func changeDuringLookupKeepsNothing() {
        let icloud = ScriptedICloud()
        let cache = UbiquityContainerCache(system: icloud.system)
        icloud.state.withLock {
            $0.flipsDuringNextLookup = true
            $0.identityAfterLookup = 2
        }
        // The read gets its answer, as every read did, but it is not kept.
        #expect(cache.url() != nil)
        #expect(cache.url() != nil)
        #expect(cache.lookupCount == 2)
        #expect(cache.url() != nil)
        #expect(cache.lookupCount == 2)
    }

    @Test("refresh() asks off the main thread; reads after it ask nothing")
    func refreshRunsOffTheMainThread() async {
        let icloud = ScriptedICloud()
        let cache = UbiquityContainerCache(system: icloud.system)
        await cache.refresh()
        #expect(cache.lookupCount == 1)
        for _ in 0..<50 { #expect(cache.url() != nil) }
        #expect(cache.lookupCount == 1)
        #expect(icloud.mainThreadLookups == 0)
    }

    @Test("startRefreshing asks once at start and again on an identity change, off the main thread")
    func startRefreshingFollowsTheIdentity() async throws {
        let icloud = ScriptedICloud(identity: nil, container: nil)
        let cache = UbiquityContainerCache(system: icloud.system)
        let center = NotificationCenter()
        cache.startRefreshing(center: center)
        cache.startRefreshing(center: center)
        try await waitForLookups(1, in: cache)
        #expect(cache.lookupCount == 1)

        let container = URL(fileURLWithPath: "/Mobile Documents/iCloud~Test")
        icloud.set(identity: 1, container: container)
        center.post(name: .NSUbiquityIdentityDidChange, object: nil)
        try await waitForLookups(2, in: cache)
        #expect(cache.lookupCount == 2)
        // The read finds the refreshed answer without asking.
        #expect(cache.url() == container)
        #expect(cache.lookupCount == 2)
        #expect(icloud.mainThreadLookups == 0)
    }

    // MARK: - The Managed Folders

    /// `ManagedPDFFileStorage.directory()` before the change, verbatim but for
    /// the container lookup it made itself (`container` is what
    /// `url(forUbiquityContainerIdentifier: nil)` returned) and the warning
    /// it logged.
    private func oldDirectory(folderName: String, container: URL?) throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = container {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }

        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    /// `createDirectoryIfNeeded(at:)`, verbatim.
    private func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func storage(folderName: String, cache: UbiquityContainerCache) -> ManagedPDFFileStorage {
        ManagedPDFFileStorage(
            folderName: folderName,
            fallbackBaseName: "Test",
            localFallbackWarning: "iCloud unavailable in a test.",
            logger: Logger.students,
            ubiquityContainer: cache
        )
    }

    @Test("In a container, the folder and a relative-path fallback land where the old lookup put them")
    func containerFolderMatchesTheOldLookup() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let icloud = ScriptedICloud(identity: 7, container: container)
        let cache = UbiquityContainerCache(system: icloud.system)
        await cache.refresh()
        let folder = storage(folderName: "Story Files", cache: cache)

        let old = try oldDirectory(folderName: "Story Files", container: container)
        #expect(try folder.directory() == old)
        #expect(old.path.hasPrefix(container.path))

        // A stored file the bookmark no longer finds, found by its relative path.
        let file = old.appendingPathComponent("Chart.pdf")
        try StudentFileThumbnailTests.makePDF().write(to: file)
        #expect(folder.resolveURL(bookmark: nil, relativePath: "Chart.pdf") == file)
        #expect(folder.resolveURL(bookmark: Data("stale".utf8), relativePath: " Chart.pdf ") == file)
        #expect(folder.resolveURL(bookmark: nil, relativePath: "Missing.pdf") == nil)

        // Fifty uses on the main thread asked FileManager nothing.
        for _ in 0..<50 { _ = try folder.directory() }
        #expect(cache.lookupCount == 1)
        #expect(icloud.mainThreadLookups == 0)
    }

    @Test("With iCloud unavailable the folder falls back to local Documents, as the old lookup did")
    func unavailableFallsBackAsBefore() throws {
        let cache = UbiquityContainerCache(system: ScriptedICloud(identity: nil, container: nil).system)
        let folder = storage(folderName: "Story Files", cache: cache)
        #expect(try folder.directory() == oldDirectory(folderName: "Story Files", container: nil))
        #expect(try folder.directory() == oldDirectory(folderName: "Story Files", container: nil))
        #expect(cache.lookupCount == 1)
    }

    @Test("Each library's folder is where the old lookup put it on this device")
    func liveFoldersMatchTheOldLookup() throws {
        let live = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        let libraries = [
            BookClubFileStorage.storage, StoryFileStorage.storage, StudentDocumentFileStorage.storage,
            ResourceFileStorage.storage, LessonFileStorage.storage
        ]
        for library in libraries {
            #expect(try library.directory() == oldDirectory(folderName: library.folderName, container: live))
        }
    }
}
