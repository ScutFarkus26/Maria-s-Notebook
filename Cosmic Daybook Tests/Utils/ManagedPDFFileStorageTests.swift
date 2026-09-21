import Foundation
import Testing
@testable import CosmicDaybook

// Existing user files on disk resolve through these folder names and this filename
// scheme, so every configuration is pinned to the literal the legacy per-library
// storage enums produced. The expected strings were computed by running the legacy
// sanitizer before it was replaced by `ManagedPDFFileStorage`; do not "fix" them.
@Suite("Managed PDF file storage")
struct ManagedPDFFileStorageTests {

    private struct Library {
        let name: String
        let storage: ManagedPDFFileStorage
        let folderName: String
        let fallbackFilename: String
    }

    private var libraries: [Library] {
        [
            Library(name: "book club", storage: BookClubFileStorage.storage,
                    folderName: "Book Club Files", fallbackFilename: "BookClub.pdf"),
            Library(name: "story", storage: StoryFileStorage.storage,
                    folderName: "Story Files", fallbackFilename: "Story.pdf"),
            Library(name: "student document", storage: StudentDocumentFileStorage.storage,
                    folderName: "Student Files", fallbackFilename: "Document.pdf"),
            Library(name: "resource", storage: ResourceFileStorage.storage,
                    folderName: "Resource Files", fallbackFilename: "Resource.pdf"),
            Library(name: "lesson", storage: LessonFileStorage.storage,
                    folderName: "Lesson Files", fallbackFilename: "Lesson.pdf")
        ]
    }

    /// The filename `storage` would give a title inside `directory`.
    private func filename(_ storage: ManagedPDFFileStorage, _ title: String?, in directory: URL) -> String {
        storage.uniqueDestination(
            in: directory,
            baseName: storage.sanitizedBaseName(title),
            extWithDot: ".pdf"
        ).lastPathComponent
    }

    private func withScratchDirectory(_ body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        try body(directory)
    }

    // MARK: - Folder names

    @Test("Each library keeps its legacy folder name")
    func folderNames() throws {
        for library in libraries {
            #expect(library.storage.folderName == library.folderName, "\(library.name)")
        }
        #expect(try BookClubFileStorage.packetFilesDirectory().lastPathComponent == "Book Club Files")
        #expect(try StoryFileStorage.storyFilesDirectory().lastPathComponent == "Story Files")
        #expect(try StudentDocumentFileStorage.studentFilesDirectory().lastPathComponent == "Student Files")
        #expect(try ResourceFileStorage.resourceFilesDirectory().lastPathComponent == "Resource Files")
        #expect(try LessonFileStorage.lessonFilesDirectory().lastPathComponent == "Lesson Files")
    }

    // MARK: - Filenames

    @Test("A title sanitizes to the legacy filename; the record id is never part of it")
    func sanitizedTitle() throws {
        let id = UUID(uuidString: "0DACE0CE-1234-4ABC-8DEF-0123456789AB")!
        try withScratchDirectory { directory in
            for library in libraries {
                let name = filename(library.storage, "Frog & Toad: Together!", in: directory)
                #expect(name == "Frog - Toad- Together.pdf", "\(library.name)")
                #expect(!name.contains(id.uuidString), "\(library.name)")
            }
        }
    }

    @Test("Punctuation, non-ASCII and edge whitespace sanitize as the legacy code did")
    func sanitizerEdgeCases() throws {
        try withScratchDirectory { directory in
            let storage = StoryFileStorage.storage
            #expect(filename(storage, "  ..Hello__World--2026.. ", in: directory) == "Hello__World-2026.pdf")
            #expect(filename(storage, "Ñandú/Émile (draft)", in: directory) == "and-mile -draft.pdf")
        }
    }

    @Test("Nil, empty and all-punctuation titles fall back to the library's stem")
    func fallbackFilenames() throws {
        try withScratchDirectory { directory in
            for library in libraries {
                for title in [nil, "", "!!!"] {
                    #expect(filename(library.storage, title, in: directory) == library.fallbackFilename,
                            "\(library.name) \(String(describing: title))")
                }
            }
        }
    }

    @Test("Colliding names are numbered from -2, and the extension stays as given")
    func collisionNumbering() throws {
        try withScratchDirectory { directory in
            let storage = BookClubFileStorage.storage
            let base = storage.sanitizedBaseName("Frog & Toad: Together!")
            #expect(base == "Frog - Toad- Together")

            try Data().write(to: directory.appendingPathComponent("Frog - Toad- Together.pdf"))
            #expect(filename(storage, "Frog & Toad: Together!", in: directory) == "Frog - Toad- Together-2.pdf")

            try Data().write(to: directory.appendingPathComponent("Frog - Toad- Together-2.pdf"))
            #expect(filename(storage, "Frog & Toad: Together!", in: directory) == "Frog - Toad- Together-3.pdf")

            // Lesson files keep the source extension, which may be absent.
            let bare = LessonFileStorage.storage.uniqueDestination(in: directory, baseName: base, extWithDot: "")
            #expect(bare.lastPathComponent == "Frog - Toad- Together")
        }
    }

    // MARK: - Error messages

    @Test("Import error messages keep their per-library wording")
    func errorMessages() {
        typealias ImportError = ManagedPDFFileStorage.ImportError
        #expect(ImportError.sourceMissing.errorDescription == "Source file is missing or unreadable.")
        #expect(ImportError.notAPDF(subject: "book club packets").errorDescription
                == "Only PDF files can be imported as book club packets.")
        #expect(ImportError.notAPDF(subject: "stories").errorDescription
                == "Only PDF files can be imported as stories.")
        #expect(ImportError.encrypted.errorDescription == "This PDF is encrypted and cannot be imported.")
        #expect(StudentDocumentFileStorage.StudentDocumentError.sourceMissing.errorDescription
                == "Source file is missing or unreadable.")
    }
}
