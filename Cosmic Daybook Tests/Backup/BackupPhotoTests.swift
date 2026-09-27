import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins note photos in the backup (format v28): carried as `photos/<name>`
/// entries, counted and verified, restored under the same name only after the
/// records import, never over a photo already there, and left out when the
/// guide turns them off.
///
/// The photo folder here is the simulator test host's own, so each test uses a
/// unique filename and removes it afterwards.
@Suite("Backup note photos", .serialized)
@MainActor
struct BackupPhotoTests {

    private func tempBackupURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupPhotoTest-\(UUID().uuidString).\(BackupFile.fileExtension)")
    }

    private func makePhoto(_ bytes: String = "jpeg bytes") throws -> (name: String, url: URL) {
        let name = "BackupPhotoTest-\(UUID().uuidString).jpg"
        let url = try PhotoStorageService.photosDirectory().appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        return (name, url)
    }

    private func seedNote(photo: String, in context: NSManagedObjectContext) {
        let note = CDNote(context: context)
        note.body = "Built the bead chain"
        note.imagePath = photo
        #expect(CoreDataTestHelpers.save(context))
    }

    @Test("A backup carries each note's photo, counted in the manifest and verified")
    func exportCarriesPhotos() async throws {
        let photo = try makePhoto()
        defer { try? FileManager.default.removeItem(at: photo.url) }
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        seedNote(photo: photo.name, in: stack.viewContext)
        let url = tempBackupURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await BackupWriter.write(viewContext: stack.viewContext, to: url, includesPhotos: true)

        let verification = try BackupReader.verifyStructure(at: url)
        #expect(verification.manifest.formatVersion == 28)
        #expect(verification.manifest.photoCount == 1)
        #expect(verification.photoCount == 1)
        #expect(verification.entryLineCounts["Note"] == 1)
    }

    @Test("With photos turned off, the backup has none and its manifest says nothing about them")
    func exportWithoutPhotos() async throws {
        let photo = try makePhoto()
        defer { try? FileManager.default.removeItem(at: photo.url) }
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        seedNote(photo: photo.name, in: stack.viewContext)
        let url = tempBackupURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await BackupWriter.write(viewContext: stack.viewContext, to: url, includesPhotos: false)

        let verification = try BackupReader.verifyStructure(at: url)
        #expect(verification.manifest.photoCount == nil)
        #expect(verification.photoCount == 0)
    }

    @Test("A note whose photo isn't on this device backs up without it")
    func missingPhotoIsLeftOut() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        seedNote(photo: "BackupPhotoTest-missing-\(UUID().uuidString).jpg", in: stack.viewContext)
        let url = tempBackupURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await BackupWriter.write(viewContext: stack.viewContext, to: url, includesPhotos: true)

        #expect(try BackupReader.verifyStructure(at: url).photoCount == 0)
    }

    @Test("A restore puts a deleted photo back under its name, with the same bytes")
    func restoreReinstallsPhoto() async throws {
        let photo = try makePhoto("original photo")
        defer { try? FileManager.default.removeItem(at: photo.url) }
        let source = try CoreDataTestHelpers.makeInMemoryStack()
        seedNote(photo: photo.name, in: source.viewContext)
        let url = tempBackupURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await BackupWriter.write(viewContext: source.viewContext, to: url, includesPhotos: true)

        try FileManager.default.removeItem(at: photo.url)
        #expect(PhotoStorageService.photoURL(for: photo.name) == nil)

        let destination = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupImporter.restore(
            from: url, into: destination.viewContext, mode: .merge,
            appRouter: AppRouter.shared, progress: { _, _ in }
        )

        let restored = try #require(PhotoStorageService.photoURL(for: photo.name))
        #expect(try Data(contentsOf: restored) == Data("original photo".utf8))
    }

    @Test("A restore never overwrites a photo already on the device")
    func restoreKeepsExistingPhoto() async throws {
        let photo = try makePhoto("from the backup")
        defer { try? FileManager.default.removeItem(at: photo.url) }
        let source = try CoreDataTestHelpers.makeInMemoryStack()
        seedNote(photo: photo.name, in: source.viewContext)
        let url = tempBackupURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await BackupWriter.write(viewContext: source.viewContext, to: url, includesPhotos: true)

        try Data("already here".utf8).write(to: photo.url)
        let decoded = try await BackupImporter.decodeArchive(at: url)
        let staging = try #require(decoded.stagedPhotos)
        let result = await BackupPhotos.installStaged(from: staging)

        #expect(result.installed == 0 && result.failed == 0)
        #expect(try Data(contentsOf: photo.url) == Data("already here".utf8))
        #expect(!FileManager.default.fileExists(atPath: staging.path), "The staging folder is removed")
    }

    @Test("Photo entry names that could leave the photo folder are refused; other paths aren't photos")
    func archivePathSafety() throws {
        #expect(try BackupPhotos.filename(fromArchivePath: "photos/ABC.jpg") == "ABC.jpg")
        #expect(try BackupPhotos.filename(fromArchivePath: "private/Note.ndjson") == nil)
        for unsafe in ["photos/", "photos/../x.jpg", "photos/.hidden.jpg", "photos/a/b.jpg"] {
            #expect(throws: (any Error).self, "\(unsafe)") {
                _ = try BackupPhotos.filename(fromArchivePath: unsafe)
            }
        }
    }
}
