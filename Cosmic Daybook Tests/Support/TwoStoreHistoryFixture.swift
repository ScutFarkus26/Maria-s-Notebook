import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// The production two-store shape, for persistent-history tests: two on-disk
/// SQLite stores with the real Private and Shared configurations from
/// `CoreDataStack.sharedModel()`, history tracking on through
/// `CoreDataStack.enableHistoryTracking`, loaded in an
/// `NSPersistentCloudKitContainer` with no CloudKit options, in a temporary
/// directory of their own. Call `removeFiles()` when done.
///
/// A write saves a Note (private store) or an AttendanceDayLock (shared
/// store — since schema 9 only the five classroom-share types live there). No
/// entity notification watches either, so a history pass over them posts
/// nothing process-wide.
@MainActor
struct TwoStoreHistoryFixture {

    /// Which store a write lands in.
    nonisolated enum Side: CaseIterable, Sendable {
        case privateStore, sharedStore

        var other: Side { self == .privateStore ? .sharedStore : .privateStore }

        /// The entity a write on this side saves.
        var entityName: String { self == .privateStore ? "Note" : "AttendanceDayLock" }
    }

    /// The author of CloudKit's own imports, so a remote change.
    static let remoteAuthor = "NSCloudKitMirroringDelegate.import"
    /// The app's author, whose transactions the history processor skips.
    static let ownAuthor = PersistentHistoryProcessor.transactionAuthor

    let container: NSPersistentCloudKitContainer
    let directory: URL
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("two-store-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = NSPersistentCloudKitContainer(
            name: CoreDataStack.modelName,
            managedObjectModel: try CoreDataStack.sharedModel()
        )
        let privateDescription = CoreDataStack.makeStoreDescription(
            url: directory.appendingPathComponent("private.sqlite"),
            configuration: CoreDataStack.privateConfiguration
        )
        let sharedDescription = CoreDataStack.makeStoreDescription(
            url: directory.appendingPathComponent("shared.sqlite"),
            configuration: CoreDataStack.sharedConfiguration
        )
        CoreDataStack.enableHistoryTracking(privateDescription)
        CoreDataStack.enableHistoryTracking(sharedDescription)
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
        let loaded = container.persistentStoreCoordinator.persistentStores
        privateStore = try #require(loaded.first { $0.configurationName == CoreDataStack.privateConfiguration })
        sharedStore = try #require(loaded.first { $0.configurationName == CoreDataStack.sharedConfiguration })
    }

    func store(_ side: Side) -> NSPersistentStore {
        side == .privateStore ? privateStore : sharedStore
    }

    /// The store's identifier, which keys the history processor's positions.
    func id(_ side: Side) -> String {
        store(side).identifier
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Saves one new row, which is one history transaction, in `side`'s store.
    /// A nil `author` is a context that never set one.
    func write(_ side: Side, as author: String? = TwoStoreHistoryFixture.remoteAuthor) throws {
        let context = container.viewContext
        context.transactionAuthor = author
        let object = NSEntityDescription.insertNewObject(forEntityName: side.entityName, into: context)
        context.assign(object, to: store(side))
        try context.save()
    }

    /// A plain history fetch after `token`, narrowed to `scope` when one is given.
    func history(
        after token: NSPersistentHistoryToken?,
        scopedTo scope: [NSPersistentStore]? = nil
    ) throws -> [NSPersistentHistoryTransaction] {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsOnly
        if let scope { request.affectedStores = scope }
        let result = try container.viewContext.execute(request) as? NSPersistentHistoryResult
        return try #require(result?.result as? [NSPersistentHistoryTransaction])
    }

    /// The token of the newest transaction in `side`'s store.
    func newestToken(_ side: Side) throws -> NSPersistentHistoryToken {
        try #require(try history(after: nil, scopedTo: [store(side)]).last?.token)
    }

    /// One history-processor read of both stores, on a background context as
    /// the actor runs it.
    func pass(after positions: [String: NSPersistentHistoryToken]) async -> PersistentHistoryProcessor.HistoryPass {
        let context = container.newBackgroundContext()
        let author = Self.ownAuthor
        return await context.perform {
            PersistentHistoryProcessor.readHistory(after: positions, author: author, in: context)
        }
    }
}
