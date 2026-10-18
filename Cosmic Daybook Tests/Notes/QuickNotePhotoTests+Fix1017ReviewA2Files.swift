import Foundation
import PhotosUI
import SwiftUI
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-17 bug-hunt fixes (a2, files and photos).
// #2: a camera shot taken while a library photo was still loading was deleted
// when the library photo landed. Camera shots aren't saved to Photos, so the
// shot existed nowhere else.
// #5: a library photo that never arrived held Save (and her typed note) until
// she removed it; nothing told her it had stalled.

@Suite("Quick Note photo review fixes (Fix1017ReviewA2Files)")
@MainActor
struct QuickNotePhotoReviewTests {

    static func libraryPhotoData() throws -> Data {
        try #require(TestImages.encoded(TestImages.quadrants(width: 320, height: 240), as: .jpeg))
    }

    static func fileExists(_ filename: String) throws -> Bool {
        let directory = try PhotoStorageService.photosDirectory()
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path)
    }

    #if os(iOS)
    @Test("A camera shot taken while a library photo loads is kept; the late library photo is deleted")
    func cameraShotSurvivesLateLibraryPhoto() async throws {
        let viewModel = QuickNoteViewModel(initialBodyText: "Pin map of Africa.")
        let item = PhotosPickerItem(itemIdentifier: "fix1017a2-camera-\(UUID().uuidString)")
        // She picked a library photo, which is still coming from iCloud Photos…
        viewModel.selectedPhotoItem = item
        viewModel.loadingPhotoItem = item

        // …then took a photo with the camera.
        let shot = UIImage(cgImage: TestImages.quadrants(width: 200, height: 200))
        viewModel.processImage(shot)
        let cameraFile = try #require(viewModel.attachedImagePath)
        defer { try? PhotoStorageService.deleteImage(filename: cameraFile) }
        #expect(viewModel.selectedPhotoItem == nil, "the camera shot replaces the pick")
        #expect(!viewModel.isLoadingPhoto, "Save no longer waits for the library photo")

        // The library photo lands afterwards.
        let library = try Self.libraryPhotoData()
        let stored = try #require(PhotoImageIO.savedPhotoJPEG(from: library))
        await viewModel.attachPhotoData(library, from: item)

        let left = try QuickNotePhotoTests.files(holding: stored)
        defer { for name in left { try? PhotoStorageService.deleteImage(filename: name) } }
        #expect(try Self.fileExists(cameraFile), "the camera shot is still on disk")
        #expect(viewModel.attachedImagePath == cameraFile, "the note keeps the camera shot")
        #expect(left.isEmpty, "the late library photo's file is gone")
    }
    #endif

    @Test("A photo that never arrives stops holding Save after the limit and says so plainly")
    func stalledPhotoGivesUp() async throws {
        let viewModel = QuickNoteViewModel(initialBodyText: "Read aloud.")
        viewModel.photoLoadLimit = .milliseconds(100)
        let item = PhotosPickerItem(itemIdentifier: "fix1017a2-stalled-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item
        let library = try Self.libraryPhotoData()
        let stored = try #require(PhotoImageIO.savedPhotoJPEG(from: library))

        var couldSaveAfterLimit = false
        var messageAfterLimit: String?
        await viewModel.loadPhoto(item) {
            try await Task.sleep(for: .milliseconds(800))
            couldSaveAfterLimit = viewModel.canSave
            messageAfterLimit = viewModel.photoLoadMessage
            return library
        }

        #expect(couldSaveAfterLimit, "Save came back once the limit passed")
        #expect(messageAfterLimit != nil, "she was told the photo didn't come")
        #expect(viewModel.selectedPhotoItem == nil)
        #expect(viewModel.attachedImagePath == nil, "the photo that came too late isn't attached")
        let left = try QuickNotePhotoTests.files(holding: stored)
        defer { for name in left { try? PhotoStorageService.deleteImage(filename: name) } }
        #expect(left.isEmpty, "and its file is deleted")
    }

    @Test("A photo that arrives within the limit is attached with no message")
    func photoWithinLimitIsAttached() async throws {
        let viewModel = QuickNoteViewModel(initialBodyText: "Read aloud.")
        viewModel.photoLoadLimit = .seconds(30)
        let item = PhotosPickerItem(itemIdentifier: "fix1017a2-ontime-\(UUID().uuidString)")
        viewModel.selectedPhotoItem = item
        let library = try Self.libraryPhotoData()

        await viewModel.loadPhoto(item) { library }

        let path = try #require(viewModel.attachedImagePath)
        defer { try? PhotoStorageService.deleteImage(filename: path) }
        #expect(viewModel.photoLoadMessage == nil)
        #expect(viewModel.canSave)
    }
}
