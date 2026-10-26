import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Which files `attach_file_to_lesson` may read (plan "Lesson file
/// attachments", Decision 4): only inside a granted or album folder, after
/// `~`, `..` and symbolic links are resolved, never Cosmic Daybook's own
/// files, and only a PDF or an image. Every refusal writes nothing.
@Suite("MCP Lesson Attachment Paths")
@MainActor
struct MCPLessonAttachmentPathTests {

    @Test("~ is expanded against the injected home folder")
    func tildeUsesInjectedHome() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let bytes = LessonFileToolFixture.pdf()
        try fixture.write(bytes, named: "circle.pdf")

        _ = try await fixture.call(
            "attach_file_to_lesson", fixture.attach("~/Documents/Workplaces/YYLI/circle.pdf")
        )

        let stored = try #require(try fixture.stored().first)
        #expect(try fixture.bytes(of: stored) == bytes)
        let containment = PathContainment(home: fixture.home)
        #expect(containment.expand("~/a.pdf")?.path == fixture.home.appendingPathComponent("a.pdf").path)
        #expect(containment.expand("~") == fixture.home)
        #expect(containment.expand("Documents/a.pdf") == nil)
        #expect(containment.expand("~someone/a.pdf") == nil)
    }

    @Test("A .docx is refused in plain words before anything is copied")
    func docxRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(Data("PK not really a document".utf8), named: "notes.docx")

        let message = try await fixture.refusal("attach_file_to_lesson", fixture.attach(source.path))

        #expect(message == "That kind of file can't be attached here. Choose a PDF or an image.")
        try fixture.expectNothingWritten()
    }

    @Test("A missing file and a folder are refused")
    func missingAndFolderRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let folder = fixture.granted.appendingPathComponent("masters", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let missing = try await fixture.refusal(
            "attach_file_to_lesson", fixture.attach(fixture.granted.appendingPathComponent("gone.pdf").path)
        )
        let isFolder = try await fixture.refusal("attach_file_to_lesson", fixture.attach(folder.path))

        #expect(missing.hasPrefix("Couldn't find that file."))
        #expect(isFolder.hasPrefix("That's a folder, not a file."))
        try fixture.expectNothingWritten()
    }

    @Test("Paths outside the granted folder are refused, naming Settings › Claude Desktop")
    func outsideRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let secret = try fixture.write(LessonFileToolFixture.pdf(), named: "secret.pdf", in: fixture.outside)
        let besideGranted = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf", in: fixture.sibling)
        let link = fixture.granted.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        let escape = fixture.granted.path + "/../../../Outside/secret.pdf"

        let cases: [(String, String)] = [
            ("outside every folder", secret.path),
            ("a `..` escape", escape),
            ("a symbolic link inside the folder pointing out", link.path),
            ("the sibling YYLI2 beside a granted YYLI", besideGranted.path)
        ]
        for (label, path) in cases {
            let message = try await fixture.refusal("attach_file_to_lesson", fixture.attach(path))
            #expect(message.contains("isn't in a folder the guide has let Claude attach files from"), "\(label)")
            #expect(message.contains("Settings › Claude Desktop › Folders Claude can attach files from"), "\(label)")
        }
        try fixture.expectNothingWritten()
    }

    @Test("The MCP token is refused even when the whole home folder is granted")
    func tokenRefused() async throws {
        let fixture = try LessonFileToolFixture(grantHome: true)
        defer { fixture.remove() }

        let message = try await fixture.refusal(
            "attach_file_to_lesson", fixture.attach("~/.cosmic-daybook/mcp.token")
        )

        #expect(message == "That file belongs to Cosmic Daybook itself, so it can't be attached.")
        try fixture.expectNothingWritten()
    }

    @Test("A path that isn't a full one is refused")
    func relativePathRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")

        let message = try await fixture.refusal("attach_file_to_lesson", fixture.attach("YYLI/circle.pdf"))

        #expect(message.contains("isn't a full path"))
        try fixture.expectNothingWritten()
    }

    @Test("With no folders granted, the refusal says none are set up")
    func noFoldersRefusal() {
        #expect(MCPAttachFolders.outsideMessage(hasFolders: false).contains("no folders are set up"))
    }

    // MARK: - The rules themselves

    @Test("A folder contains a path only up to a slash, and the live rules refuse the token folder")
    func containmentRules() {
        #expect(PathContainment.contains("/Users/d/YYLI", "/Users/d/YYLI/a.pdf"))
        #expect(PathContainment.contains("/Users/d/YYLI", "/Users/d/YYLI"))
        #expect(!PathContainment.contains("/Users/d/YYLI", "/Users/d/YYLI2/a.pdf"))
        #expect(PathContainment.contains("/", "/a.pdf"))
        let live = PathContainment.live
        #expect(live.refused.contains { $0.lastPathComponent == ".cosmic-daybook" })
    }

    @Test("Allowed roots are the granted folders then the album folders, each once, from their bookmarks")
    func allowedRootsFromBookmarks() throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let suite = "MCPLessonAttachmentPathTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let albums = fixture.home.appendingPathComponent("Albums", isDirectory: true)
        try FileManager.default.createDirectory(at: albums, withIntermediateDirectories: true)
        let grantedMark = try SecurityScopedBookmark.make(for: fixture.granted)
        defaults.set([grantedMark], forKey: MCPAttachFolders.bookmarksKey)
        defaults.set(
            [try SecurityScopedBookmark.make(for: albums), grantedMark], forKey: UserDefaultsKeys.albumsFolderBookmarks
        )

        let roots = MCPAttachFolders.allowedRoots(defaults: defaults).map { PathContainment.realPath(of: $0) }

        #expect(roots == [PathContainment.realPath(of: fixture.granted), PathContainment.realPath(of: albums)])
    }

    @Test("The attach folders are backed up but never synced to other devices")
    func grantKeyStaysOnThisMac() {
        let key = UserDefaultsKeys.aiMCPAttachFolderBookmarks
        #expect(BackupPreferencesService.preferenceKeys.contains(key))
        #expect(BackupPreferencesService.mergePolicy(for: key) == .unionArray)
        #expect(!SyncedPreferencesStore.syncedKeys.contains(key))
        #expect(!SyncedPreferencesStore.syncedKeyPrefixes.contains { key.hasPrefix($0) })
        #expect(!SettingsExportService.transferKeys.contains(key))
    }
}
