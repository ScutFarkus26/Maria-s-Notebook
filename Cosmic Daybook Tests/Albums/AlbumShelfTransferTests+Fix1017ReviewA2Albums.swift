import Foundation
import Testing
@testable import CosmicDaybook

/// Review of the 2026-10-17 album fixes, part A: copies on their way to the
/// shelf (4) and albums still downloading from iCloud (6).
@Suite("Albums: copying to and from iCloud (bug hunt 10-17, review A2)", .serialized)
@MainActor
struct AlbumShelfTransferFix1017ReviewA2AlbumsTests {
    private typealias Fixture = AlbumShelfFixture

    /// Counts calls from any thread.
    nonisolated final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }

    /// Downloads that wait for one another: each waits until `expected` have
    /// started (or a second has passed), so downloads made one at a time
    /// never overlap.
    actor DownloadGate {
        let expected: Int
        private var started = 0
        private var inFlight = 0
        private(set) var mostAtOnce = 0

        init(expected: Int) { self.expected = expected }

        func arrive() async {
            started += 1
            inFlight += 1
            mostAtOnce = max(mostAtOnce, inFlight)
            let deadline = ContinuousClock.now + .seconds(1)
            while started < expected, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            inFlight -= 1
        }
    }

    // MARK: 4 Copies on their way to the shelf

    @Test("A copy to iCloud gives up when another app holds the file, instead of waiting for good")
    func copyGivesUpOnAHeldFile() async throws {
        let folders = try Fixture.Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let source = folders.chosen.appendingPathComponent("Held.pdf")
        try Data("held".utf8).write(to: source)
        let destination = folders.shelf.appendingPathComponent("Held.pdf")
        let release = DispatchSemaphore(value: 0)
        // Another app writing the album: it holds the file until released.
        await withCheckedContinuation { (held: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                var error: NSError?
                NSFileCoordinator(filePresenter: nil).coordinate(
                    writingItemAt: source, options: .forReplacing, error: &error
                ) { _ in
                    held.resume()
                    _ = release.wait(timeout: .now() + 10)
                }
            }
        }

        let start = ContinuousClock.now
        await #expect(throws: (any Error).self) {
            try await UbiquitousFile.coordinatedCopy(from: source, to: destination, timeout: .milliseconds(300))
        }
        let waited = ContinuousClock.now - start
        release.signal()

        #expect(waited < .seconds(5))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("Copies left on their way to the shelf go after an hour; a fresh one, other files and albums stay")
    func stalePartialCopiesAreCleared() throws {
        let folders = try Fixture.Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let album = folders.shelf.appendingPathComponent("Botany.pdf")
        try Data("album".utf8).write(to: album)
        let partial = AlbumICloudShelf.partialURL(for: album)
        try Data("half".utf8).write(to: partial)
        // A copy keeps its source's dates, so one being written now can look old.
        try ShelfReviewFixture.setDates(partial, Date().addingTimeInterval(-2 * 24 * 3600))
        let hidden = folders.shelf.appendingPathComponent(".DS_Store")
        try Data("finder".utf8).write(to: hidden)
        let visible = folders.shelf.appendingPathComponent("Botany.partial")
        try Data("mine".utf8).write(to: visible)

        #expect(AlbumICloudShelf.removeStalePartials(in: folders.shelf).isEmpty)
        #expect(FileManager.default.fileExists(atPath: partial.path))

        let later = Date().addingTimeInterval(2 * 3600)
        #expect(AlbumICloudShelf.removeStalePartials(in: folders.shelf, now: later) == [partial.lastPathComponent])
        #expect(try ShelfReviewFixture.shelfContents(folders) == [".DS_Store", "Botany.partial", "Botany.pdf"])
    }

    @Test("Opening the albums clears a copy an earlier session left on the shelf")
    func loadClearsLeftoverCopies() async throws {
        let name = Fixture.albumName("Swept")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let partial = AlbumICloudShelf.partialURL(for: kept)
            try Data("half".utf8).write(to: partial)
            library.stalePartialAge = 0

            library.load(from: library.withShelf([]))
            await library.shelfSweepTask?.value

            #expect(!FileManager.default.fileExists(atPath: partial.path))
            #expect(FileManager.default.fileExists(atPath: kept.path))
        }
    }

    // MARK: 6 Albums still downloading

    @Test("Albums still in iCloud download at the same time, not one after another")
    func pendingAlbumsDownloadTogether() async throws {
        let names = (1...3).map { Fixture.albumName("Evicted \($0)") }
        try await Fixture.withLibrary(names: names) { library, folders in
            for name in names {
                let placeholder = UbiquitousFile.placeholderURL(for: folders.shelf.appendingPathComponent(name))
                try Data("stub".utf8).write(to: placeholder)
            }
            let gate = DownloadGate(expected: names.count)
            library.downloadAlbum = { _ in
                await gate.arrive()
                return nil
            }

            library.load(from: library.withShelf([]))

            #expect(library.pendingShelfAlbumNames == Set(names))
            #expect(await AlbumTestSupport.waitUntil { library.shelfDownloadTask == nil })
            #expect(await gate.mostAtOnce == names.count)
        }
    }

    @Test("Coming back to albums that couldn't download tries again without putting the spinner back")
    func failedDownloadRetriesQuietly() async throws {
        let name = Fixture.albumName("Offline")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let placeholder = UbiquitousFile.placeholderURL(for: folders.shelf.appendingPathComponent(name))
            try Data("stub".utf8).write(to: placeholder)
            let attempts = Counter()
            library.downloadAlbum = { _ in
                attempts.increment()
                return nil
            }
            Fixture.withStoredBookmarks([]) { library.bootstrapIfNeeded() }
            #expect(await AlbumTestSupport.waitUntil { library.shelfDownloadTask == nil })
            guard case .failed = library.state else {
                Issue.record("Expected the download failure to be shown, got \(library.state)")
                return
            }

            Fixture.withStoredBookmarks([]) { library.refreshIfChanged() }

            guard case .failed = library.state else {
                Issue.record("Coming back put \"Opening albums…\" up again: \(library.state)")
                return
            }
            #expect(await AlbumTestSupport.waitUntil { library.shelfDownloadTask == nil })
            #expect(attempts.value == 2)
            guard case .failed = library.state else {
                Issue.record("Expected the failure to stay, got \(library.state)")
                return
            }
        }
    }
}
