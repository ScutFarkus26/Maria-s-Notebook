import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

// Bug hunt 2026-10-17, #28. Describe Photo and Suggest Tags read the note's
// photo straight from the file, on the main thread, without waiting for iCloud
// to bring a photo taken on another device: it wasn't there, so Describe Photo
// said it isn't available and Suggest Tags went on without the photo.

@Suite("Note photo for Apple Intelligence (Fix1017Ph)")
struct NoteAIPhotoTests {

    @Test("A photo still in iCloud is downloaded before Apple Intelligence reads it")
    func downloadsBeforeReading() async throws {
        let data = try #require(TestImages.encoded(TestImages.quadrants(width: 640, height: 480), as: .jpeg))
        let folder = try PhotoStorageService.localPhotosDirectory()
        let filename = "fix1017ph-ai-\(UUID().uuidString).jpg"
        defer { try? PhotoStorageService.deleteLocalImage(filename: filename) }

        // Not on this device yet: the download is what brings it.
        let image = await PhotoStorageService.imageForAI(filename: filename, maxPixelSize: 320) { name in
            try? data.write(to: folder.appendingPathComponent(name))
        }

        let read = try #require(image, "read after the download, not before")
        #expect(read.width == 320)
        #expect(read.height == 240)
    }

    @Test("A photo that never arrives gives no image")
    func missingPhotoGivesNothing() async {
        let image = await PhotoStorageService.imageForAI(
            filename: "fix1017ph-absent-\(UUID().uuidString).jpg", maxPixelSize: 320
        ) { _ in }
        #expect(image == nil)
    }
}
