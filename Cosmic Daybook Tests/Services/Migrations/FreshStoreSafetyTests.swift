import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Two things that hurt a notebook starting from nothing — the empty
/// Production notebook before its restore, a Reset Local Cache, a new device.
@Suite("Fresh-store safety", .serialized)
@MainActor
struct FreshStoreSafetyTests {

    /// Drops a stray photo in the local folder and returns its name.
    private func strayPhoto() throws -> String {
        let name = "fresh-store-\(UUID().uuidString).jpg"
        let url = try PhotoStorageService.localPhotosDirectory().appendingPathComponent(name)
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        return name
    }

    private func exists(_ name: String) throws -> Bool {
        let url = try PhotoStorageService.localPhotosDirectory().appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path)
    }

    @Test("An empty store deletes no local note photos")
    func emptyStoreKeepsPhotos() throws {
        let name = try strayPhoto()
        defer { try? PhotoStorageService.deleteLocalImage(filename: name) }
        let context = try CoreDataTestHelpers.makeSplitStoreContext()

        DataCleanupService.cleanupOrphanedNoteImages(using: context, firstDownloadPending: false)
        #expect(try exists(name), "a store with no notes can't judge which photos are orphaned")
    }

    @Test("A store still downloading deletes no local note photos")
    func downloadingStoreKeepsPhotos() throws {
        let name = try strayPhoto()
        defer { try? PhotoStorageService.deleteLocalImage(filename: name) }
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let note = CDNote(context: context)
        note.body = "Has a note, but the rest is still on its way"
        #expect(CoreDataTestHelpers.save(context))

        DataCleanupService.cleanupOrphanedNoteImages(using: context, firstDownloadPending: true)
        #expect(try exists(name))
    }

    @Test("A complete store still clears photos no note references")
    func completeStoreClearsOrphans() throws {
        let name = try strayPhoto()
        defer { try? PhotoStorageService.deleteLocalImage(filename: name) }
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let note = CDNote(context: context)
        note.body = "A note with no photo"
        #expect(CoreDataTestHelpers.save(context))

        DataCleanupService.cleanupOrphanedNoteImages(using: context, firstDownloadPending: false)
        #expect(try !exists(name))
    }

    @Test("Reset Local Cache names SQLite's own WAL and SHM files")
    func resetNamesSQLiteCompanions() {
        let store = URL(fileURLWithPath: "/tmp/notebook/private.sqlite")
        #expect(CoreDataStack.storeFiles(for: store).map(\.lastPathComponent) == [
            "private.sqlite", "private.sqlite-wal", "private.sqlite-shm"
        ])
    }
}
