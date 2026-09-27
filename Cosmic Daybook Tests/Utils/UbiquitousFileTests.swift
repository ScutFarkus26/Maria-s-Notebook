import Foundation
import Testing
@testable import CosmicDaybook

/// Pins how the app reads iCloud files that are not on the device yet (an iOS
/// `.<name>.icloud` placeholder), and that the coordinated writes, moves and
/// deletes do what the plain calls did. A scratch folder stands in for the
/// container: the simulator has no iCloud account, so a placeholder here is a
/// file this test writes, which is exactly what iOS leaves on disk.
@Suite("iCloud file access")
struct UbiquitousFileTests {

    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        try await body(directory)
    }

    /// Writes the placeholder iOS keeps for `url` while it is still in iCloud.
    private func writePlaceholder(for url: URL) throws {
        try Data("placeholder".utf8).write(to: UbiquitousFile.placeholderURL(for: url))
    }

    // MARK: - Presence

    @Test("The placeholder is the hidden .<name>.icloud file beside the real name")
    func placeholderName() {
        let url = URL(fileURLWithPath: "/tmp/Lesson Files/Math/Bead Chains.pdf")
        #expect(UbiquitousFile.placeholderURL(for: url).path == "/tmp/Lesson Files/Math/.Bead Chains.pdf.icloud")
    }

    @Test("A file only in iCloud counts as available and as needing a download")
    func placeholderOnly() async throws {
        try await withScratchDirectory { directory in
            let url = directory.appendingPathComponent("Story.pdf")
            try writePlaceholder(for: url)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(UbiquitousFile.isAvailable(url))
            #expect(UbiquitousFile.needsDownload(url))
        }
    }

    @Test("A local file is available and needs no download; a missing one is neither")
    func localAndMissing() async throws {
        try await withScratchDirectory { directory in
            let local = directory.appendingPathComponent("Local.pdf")
            try Data("pdf".utf8).write(to: local)
            #expect(UbiquitousFile.isAvailable(local))
            #expect(!UbiquitousFile.needsDownload(local))
            #expect(await UbiquitousFile.ensureLocal(local) == local)

            let missing = directory.appendingPathComponent("Missing.pdf")
            #expect(!UbiquitousFile.isAvailable(missing))
            #expect(!UbiquitousFile.needsDownload(missing))
            #expect(await UbiquitousFile.ensureLocal(missing) == nil)
            #expect(await UbiquitousFile.localURL(for: missing) == missing)
        }
    }

    // MARK: - Coordinated file operations

    @Test("Coordinated write, copy and move leave the same files the plain calls did")
    func coordinatedWriteCopyMove() async throws {
        try await withScratchDirectory { directory in
            let written = directory.appendingPathComponent("Written.jpg")
            try UbiquitousFile.coordinatedWrite(Data("photo".utf8), to: written)
            #expect(try Data(contentsOf: written) == Data("photo".utf8))

            let copied = directory.appendingPathComponent("Copied.jpg")
            try UbiquitousFile.coordinatedCopy(from: written, to: copied)
            #expect(try Data(contentsOf: copied) == Data("photo".utf8))
            #expect(FileManager.default.fileExists(atPath: written.path))

            let moved = directory.appendingPathComponent("Moved.jpg")
            try UbiquitousFile.coordinatedMove(from: copied, to: moved)
            #expect(try Data(contentsOf: moved) == Data("photo".utf8))
            #expect(!FileManager.default.fileExists(atPath: copied.path))
        }
    }

    @Test("A coordinated copy onto an existing name fails, as copyItem did")
    func coordinatedCopyRefusesExisting() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("A.pdf")
            let destination = directory.appendingPathComponent("B.pdf")
            try Data("a".utf8).write(to: source)
            try Data("b".utf8).write(to: destination)
            #expect(throws: (any Error).self) {
                try UbiquitousFile.coordinatedCopy(from: source, to: destination)
            }
            #expect(try Data(contentsOf: destination) == Data("b".utf8))
        }
    }

    @Test("A coordinated delete removes a local file, a placeholder-only file, and ignores a missing one")
    func coordinatedDelete() async throws {
        try await withScratchDirectory { directory in
            let local = directory.appendingPathComponent("Local.pdf")
            try Data("pdf".utf8).write(to: local)
            try UbiquitousFile.coordinatedDelete(local)
            #expect(!FileManager.default.fileExists(atPath: local.path))

            let remote = directory.appendingPathComponent("Remote.pdf")
            try writePlaceholder(for: remote)
            try UbiquitousFile.coordinatedDelete(remote)
            #expect(!UbiquitousFile.isAvailable(remote))

            try UbiquitousFile.coordinatedDelete(directory.appendingPathComponent("Missing.pdf"))
        }
    }

    // MARK: - Managed folders

    @Test("A managed PDF still in iCloud resolves, so Open stays offered, and can be deleted")
    func managedPlaceholderResolves() async throws {
        try await withScratchDirectory { container in
            var storage = StoryFileStorage.storage
            storage.ubiquityContainer = UbiquityContainerCache(system: .init(
                identity: { 1 },
                containerURL: { container }
            ))
            let file = try storage.directory().appendingPathComponent("Marigold Cove.pdf")
            try writePlaceholder(for: file)

            let resolved = storage.resolveURL(bookmark: nil, relativePath: "Marigold Cove.pdf")
            #expect(resolved?.standardizedFileURL == file.standardizedFileURL)
            #expect(storage.resolveURL(bookmark: nil, relativePath: "Missing.pdf") == nil)

            // Its name is taken for a new import too.
            let next = storage.uniqueDestination(
                in: try storage.directory(), baseName: "Marigold Cove", extWithDot: ".pdf"
            )
            #expect(next.lastPathComponent == "Marigold Cove-2.pdf")

            try storage.deleteIfManaged(file)
            #expect(!UbiquitousFile.isAvailable(file))
        }
    }

    // MARK: - Note photos

    @Test("Note photos sync from the container root, outside the user-visible Documents folder")
    func notePhotoFolderIsPrivate() async throws {
        try await withScratchDirectory { container in
            let cache = UbiquityContainerCache(system: .init(identity: { 1 }, containerURL: { container }))
            let directory = try #require(PhotoStorageService.iCloudPhotosDirectory(container: cache))
            #expect(directory.lastPathComponent == "Note Photos")
            #expect(directory.deletingLastPathComponent().standardizedFileURL == container.standardizedFileURL)
            #expect(!directory.pathComponents.contains("Documents"))
        }
    }

    @Test("Without iCloud there is no iCloud photo folder, so photos stay local")
    func notePhotoFolderWithoutICloud() {
        let cache = UbiquityContainerCache(system: .init(identity: { nil }, containerURL: { nil }))
        #expect(PhotoStorageService.iCloudPhotosDirectory(container: cache) == nil)
    }

    #if !os(macOS)
    @Test("The download sweep leaves backups in iCloud and fetches everything else")
    func sweepSkipsBackups() {
        let root = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~Test")
        #expect(UbiquitousDownloadSweep.isBackup(root.appendingPathComponent("Documents/Backups/a.cdbackup")))
        #expect(!UbiquitousDownloadSweep.isBackup(root.appendingPathComponent("Documents/Lesson Files/a.pdf")))
        #expect(!UbiquitousDownloadSweep.isBackup(root.appendingPathComponent("Note Photos/a.jpg")))
    }
    #endif
}
