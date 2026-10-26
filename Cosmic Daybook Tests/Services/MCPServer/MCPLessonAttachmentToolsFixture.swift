import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// A scratch Mac for the lesson-file tools: a home folder (what `~` means),
/// a granted folder inside it at Documents/Workplaces/YYLI, a sibling YYLI2
/// and an Outside folder that aren't granted, the MCP token's folder, a
/// scratch iCloud container for Lesson Files, a Trash that only records what
/// it was given, and an in-memory notebook with the lesson "Area of a Circle"
/// (Geometry › Circle). Folder access is a no-op: the simulator has no sandbox.
@MainActor
struct LessonFileToolFixture {
    /// Records what went to the Trash instead of moving it.
    nonisolated final class TrashLog: Sendable {
        private let given = Mutex<[URL]>([])
        func move(_ urls: [URL]) { given.withLock { $0 += urls } }
        var urls: [URL] { given.withLock { $0 } }
    }

    /// An attachment as the store holds it, read through a context of its own.
    struct Stored: Equatable {
        let id: UUID?
        let lessonID: UUID?
        let fileName: String
        let title: String
        let path: String
        let size: Int64
        let sizeFormatted: String
        let fileType: String
        let notes: String
        let scope: AttachmentScope
        let modifiedAt: Date?
    }

    let root: URL
    let home: URL
    /// ~/Documents/Workplaces/YYLI, the granted folder.
    let granted: URL
    let sibling: URL
    let outside: URL
    let storage: ManagedPDFFileStorage
    let trash = TrashLog()
    let stack: CoreDataStack
    let lesson: CDLesson
    let roots: [URL]

    var context: NSManagedObjectContext { stack.viewContext }

    /// `grantHome` grants the whole home folder instead of YYLI.
    init(grantHome: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPLessonAttachmentTools-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        let workplaces = home.appendingPathComponent("Documents/Workplaces", isDirectory: true)
        granted = workplaces.appendingPathComponent("YYLI", isDirectory: true)
        sibling = workplaces.appendingPathComponent("YYLI2", isDirectory: true)
        outside = home.appendingPathComponent("Outside", isDirectory: true)
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let tokenFolder = home.appendingPathComponent(".cosmic-daybook", isDirectory: true)
        for folder in [granted, sibling, outside, container, tokenFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("secret-token".utf8).write(to: tokenFolder.appendingPathComponent("mcp.token"))

        var storage = LessonFileStorage.storage
        storage.ubiquityContainer = UbiquityContainerCache(system: .init(identity: { 1 }, containerURL: { container }))
        self.storage = storage
        roots = grantHome ? [home] : [granted]

        stack = try CoreDataTestHelpers.makeInMemoryStack()
        lesson = CoreDataTestHelpers.seedLesson(
            in: stack.viewContext, name: "Area of a Circle", area: "Geometry", sequence: "Circle"
        )
        lesson.id = UUID()
        try stack.viewContext.save()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Tools

    var files: MCPLessonFiles {
        let roots = self.roots
        let trash = self.trash
        return MCPLessonFiles(
            folders: MCPAttachFolders.Access(
                containment: PathContainment(home: home),
                roots: { roots },
                startAccess: { _ in false },
                stopAccess: { _ in }
            ),
            storage: storage,
            trash: { trash.move($0) }
        )
    }

    var tools: [MCPToolDefinition] {
        let context = self.context
        return MCPNotebookTools.makeTools(context: { context }, lessonFiles: files)
    }

    func call(_ name: String, _ arguments: [String: JSONValue]) async throws -> String {
        let tool = try #require(tools.first { $0.name == name }, "no tool \(name)")
        return try await tool.handler(arguments)
    }

    /// The message of the refusal the call must end in. A call that succeeds
    /// is recorded as a failure.
    func refusal(_ name: String, _ arguments: [String: JSONValue]) async throws -> String {
        do {
            let text = try await call(name, arguments)
            Issue.record("expected \(name) to refuse, but it replied: \(text)")
            return ""
        } catch let error as MCPToolError {
            return error.message
        }
    }

    /// The arguments of an attach to this lesson, by id.
    func attach(
        _ path: String, title: String? = nil, note: String? = nil, replace: Bool? = nil
    ) -> [String: JSONValue] {
        var arguments: [String: JSONValue] = [
            "lesson": .string(lesson.id?.uuidString ?? ""), "path": .string(path)
        ]
        if let title { arguments["title"] = .string(title) }
        if let note { arguments["source_note"] = .string(note) }
        if let replace { arguments["replace_existing"] = .bool(replace) }
        return arguments
    }

    // MARK: - Files

    /// Writes `data` at `name` inside `folder` (default: the granted folder).
    @discardableResult
    func write(_ data: Data, named name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? granted).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    static func pdf(_ variant: CGFloat = 0.5) -> Data {
        LessonAttachmentServiceTests.pdf(size: CGSize(width: 612 + variant * 100, height: 792), shade: variant)
    }

    static func png() -> Data {
        LessonAttachmentServiceTests.png()
    }

    // MARK: - The store

    /// Every attachment the store holds, read through a fresh context, oldest first.
    func stored() throws -> [Stored] {
        let fresh = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        fresh.persistentStoreCoordinator = context.persistentStoreCoordinator
        let request = CDFetchRequest(CDLessonAttachment.self)
        request.sortDescriptors = [NSSortDescriptor(key: "attachedAt", ascending: true)]
        return try fresh.fetch(request).map { record in
            Stored(
                id: record.id, lessonID: record.lesson?.id, fileName: record.fileName, title: record.title,
                path: record.fileRelativePath, size: record.fileSizeBytes, sizeFormatted: record.fileSizeFormatted,
                fileType: record.fileType, notes: record.notes, scope: record.scope, modifiedAt: record.modifiedAt
            )
        }
    }

    /// The bytes of a stored attachment's file in Lesson Files.
    func bytes(of stored: Stored) throws -> Data {
        try Data(contentsOf: storage.resolve(relativePath: stored.path))
    }

    /// The files in the lesson's Lesson Files folder (Geometry/Circle).
    func lessonFolderNames() throws -> [String] {
        let folder = try storage.directory().appendingPathComponent("Geometry/Circle", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// Nothing was written: no record, no copy, no pending change.
    func expectNothingWritten(_ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try stored().isEmpty, comment, sourceLocation: sourceLocation)
        #expect(try lessonFolderNames().isEmpty, comment, sourceLocation: sourceLocation)
        #expect(!context.hasChanges, comment, sourceLocation: sourceLocation)
    }
}
