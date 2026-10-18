import CoreData
import Foundation
import PhotosUI
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

// Bug hunt 2026-10-17, #17. Save in Quick Note was enabled on text alone, so a
// photo still coming from iCloud Photos (seconds for an original) missed the
// note. When it arrived, the note had already saved, so nothing cleaned the
// photo's file up: it stayed in iCloud with no note pointing at it.

@Suite("Quick Note photo timing (Fix1017Ph)")
@MainActor
struct QuickNotePhotoTests {

    static func photoData() throws -> Data {
        try #require(TestImages.encoded(TestImages.quadrants(width: 320, height: 240), as: .jpeg))
    }

    /// The files in the folder new note photos are written to that hold
    /// exactly `jpeg` (other suites write their own photos there meanwhile).
    static func files(holding jpeg: Data) throws -> [String] {
        let directory = try PhotoStorageService.photosDirectory()
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))) == jpeg
        }
    }

    @Test("Save waits while a picked photo is still loading")
    func saveWaitsForPhoto() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let viewModel = QuickNoteViewModel(initialBodyText: "Built the trinomial cube.")
        let item = PhotosPickerItem(itemIdentifier: "fix1017ph-loading-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item

        // The sheet's onChange starts the load; the photo hasn't arrived yet.
        viewModel.loadPhoto(item)

        #expect(!viewModel.saveNote(viewContext: stack.viewContext, saveCoordinator: .preview))
        #expect(!viewModel.didSave)
        #expect(!stack.viewContext.hasChanges, "no note made without its photo")
    }

    @Test("Save is off while the photo loads and comes back when it fails to load")
    func saveComesBackAfterFailedLoad() async {
        let viewModel = QuickNoteViewModel(initialBodyText: "Read aloud.")
        let item = PhotosPickerItem(itemIdentifier: "fix1017ph-fails-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item
        #expect(viewModel.canSave)

        var wasOffWhileLoading = false
        await viewModel.loadPhoto(item) {
            wasOffWhileLoading = !viewModel.canSave && viewModel.hasUnsavedContent
            throw CocoaError(.fileReadUnknown)
        }

        #expect(wasOffWhileLoading, "Save waited, and closing asks first")
        #expect(viewModel.canSave)
        #expect(!viewModel.isLoadingPhoto)
    }

    @Test("Taking the photo off or discarding the note ends the wait")
    func removingEndsWait() {
        let viewModel = QuickNoteViewModel(initialBodyText: "Read aloud.")
        let item = PhotosPickerItem(itemIdentifier: "fix1017ph-removed-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item
        viewModel.loadPhoto(item)
        #expect(!viewModel.canSave)

        // The thumbnail's remove button clears the pick; the sheet's onChange passes nil.
        viewModel.selectedPhotoItem = nil
        viewModel.loadPhoto(nil)
        #expect(viewModel.canSave)

        viewModel.selectedPhotoItem = item
        viewModel.loadPhoto(item)
        viewModel.discardUnsavedPhoto()
        #expect(!viewModel.isLoadingPhoto)
        #expect(viewModel.selectedPhotoItem == nil, "so the photo is deleted when it lands")
    }

    @Test("A photo that arrives after the note saved is deleted, not left in iCloud")
    func latePhotoIsDeleted() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let viewModel = QuickNoteViewModel(initialBodyText: "Read aloud.")
        let item = PhotosPickerItem(itemIdentifier: "fix1017ph-late-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item
        #expect(viewModel.saveNote(viewContext: stack.viewContext, saveCoordinator: .preview))
        let photo = try Self.photoData()
        let stored = try #require(PhotoImageIO.savedPhotoJPEG(from: photo))
        #expect(try Self.files(holding: stored).isEmpty)

        await viewModel.attachPhotoData(photo, from: item)

        let left = try Self.files(holding: stored)
        defer { for name in left { try? PhotoStorageService.deleteImage(filename: name) } }
        #expect(left.isEmpty, "the late photo's file is gone")
        #expect(viewModel.attachedImagePath == nil)
        #expect(viewModel.attachedImage == nil)
    }
}
