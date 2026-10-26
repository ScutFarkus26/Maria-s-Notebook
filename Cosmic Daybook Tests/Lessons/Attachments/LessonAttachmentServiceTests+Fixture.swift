import CoreData
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

/// The scratch container, stand-in Trash and test files the service tests share.
extension LessonAttachmentServiceTests {
    // MARK: - Fixture

    /// Stands in for the Trash: moves each file it's given into a folder of
    /// its own, and remembers what it was given.
    final class FakeTrash {
        let folder: URL
        private(set) var given: [URL] = []

        init(folder: URL) {
            self.folder = folder
        }

        func move(_ urls: [URL]) {
            for url in urls {
                given.append(url)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let destination = folder.appendingPathComponent("\(given.count)-\(url.lastPathComponent)")
                try? FileManager.default.moveItem(at: url, to: destination)
            }
        }

        /// The files now in the stand-in Trash.
        var contents: [URL] {
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        }
    }

    /// A scratch container, its Lesson Files folder, a lesson to attach to,
    /// and a folder of source files outside the container.
    struct Scratch {
        let root: URL
        let storage: ManagedPDFFileStorage
        let sources: URL
        let trash: FakeTrash
        let stack: CoreDataStack
        let lesson: CDLesson

        var context: NSManagedObjectContext { stack.viewContext }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LessonAttachmentServiceTests-\(UUID().uuidString)", isDirectory: true)
            let container = root.appendingPathComponent("Container", isDirectory: true)
            sources = root.appendingPathComponent("Sources", isDirectory: true)
            let trashFolder = root.appendingPathComponent("Trash", isDirectory: true)
            for folder in [container, sources, trashFolder] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            var storage = LessonFileStorage.storage
            storage.ubiquityContainer = UbiquityContainerCache(
                system: .init(identity: { 1 }, containerURL: { container })
            )
            self.storage = storage
            trash = FakeTrash(folder: trashFolder)
            stack = try CoreDataTestHelpers.makeInMemoryStack()
            lesson = CoreDataTestHelpers.seedLesson(
                in: stack.viewContext, name: "Area of a Circle", area: "Geometry", sequence: "Circle"
            )
            lesson.id = UUID()
            try stack.viewContext.save()
        }

        /// The service over this scratch folder, saving with `save`, with
        /// `otherNotebooks` (none by default, whatever the app has showing)
        /// as the other stores that use these files.
        func service(
            isSampleClassroom: Bool = false,
            save: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() },
            otherNotebooks: @escaping () -> [NSManagedObjectContext] = { [] }
        ) -> LessonAttachmentService {
            let trash = self.trash
            return LessonAttachmentService(
                context: context, storage: storage, isSampleClassroom: isSampleClassroom,
                save: save, trash: { trash.move($0) }, otherNotebooks: otherNotebooks
            )
        }

        func write(_ data: Data, named name: String) throws -> URL {
            let url = sources.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        /// A file of `size` bytes that takes no space: `header`, then zeros.
        func sparseFile(named name: String, size: Int64, header: Data = Data()) throws -> URL {
            let url = try write(header, named: name)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
            return url
        }

        /// Where an attachment's file is on disk.
        func file(of attachment: CDLessonAttachment) throws -> URL {
            try storage.resolve(relativePath: attachment.fileRelativePath)
        }

        /// The names of the files in the lesson's folder (Geometry/Circle).
        func lessonFolderNames() throws -> [String] {
            let folder = try storage.directory().appendingPathComponent("Geometry/Circle", isDirectory: true)
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }

        /// The record as the store holds it, read through a context of its own.
        func persisted(_ id: UUID?) throws -> Stored? {
            let id = try #require(id)
            let fresh = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            fresh.persistentStoreCoordinator = context.persistentStoreCoordinator
            let request = CDFetchRequest(CDLessonAttachment.self)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let record = try fresh.fetch(request).first else { return nil }
            return Stored(
                path: record.fileRelativePath, size: record.fileSizeBytes,
                modifiedAt: record.modifiedAt, notes: record.notes
            )
        }

        /// `url` alone was given to the Trash, and its file is there, whole.
        func expectOnlyTrashed(_ url: URL, holding bytes: Data) throws {
            #expect(trash.given.map(\.standardizedFileURL) == [url.standardizedFileURL])
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let trashed = try #require(trash.contents.first)
            #expect(try Data(contentsOf: trashed) == bytes)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    struct SaveRefused: Error {}

    /// An attachment's stored values.
    struct Stored: Equatable {
        let path: String
        let size: Int64
        let modifiedAt: Date?
        let notes: String
    }

    /// A one-page PDF; a different `size` gives a different byte count.
    static func pdf(size: CGSize = CGSize(width: 612, height: 792), shade: CGFloat = 0.5) -> Data {
        StudentFileThumbnailTests.makePDF(size: size, shade: shade)
    }

    /// A small grey PNG.
    static func png(gray: CGFloat = 0.3) -> Data {
        let output = NSMutableData()
        guard let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.png.identifier as CFString, 1, nil
              ) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }

    static let earlier = Date(timeIntervalSince1970: 1_790_000_000)
}
