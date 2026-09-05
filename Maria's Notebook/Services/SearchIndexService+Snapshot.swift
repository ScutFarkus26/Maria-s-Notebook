//
//  SearchIndexService+Snapshot.swift
//  Maria's Notebook
//
//  The on-disk search index snapshot and the launch-time refresh that uses it.
//
//  Every cold launch used to fetch every student, lesson, note, todo, and work
//  item on a background context and re-tokenize all of it, then insert the
//  result on the main actor. The snapshot keeps the tokenization *input* — one
//  (result, text, objectURI) entry per indexed object — in Caches, tagged with
//  the store's identity and the persistent-history token current when it was
//  written. On the next launch the index is rebuilt from the snapshot off the
//  main actor, and only the objects that changed since — inserts, updates,
//  and deletes replayed from persistent history — touch Core Data.
//
//  Anything that makes the snapshot untrustworthy makes it unusable by
//  construction: a different store (Reset Local Cache, a quarantined store,
//  the sample classroom) has a different identity; a token older than the
//  retained history fails the history fetch; a bulk import trips the change
//  limit. All three fall back to the full pass, which writes a fresh snapshot.
//

import CoreData
import CryptoKit
import Foundation
import OSLog

// MARK: - Snapshot

nonisolated struct SearchIndexSnapshot: Codable, Sendable {
    static let currentVersion = 1

    struct Entry: Codable, Sendable, Hashable {
        var result: SearchResult
        var text: String
        /// `NSManagedObjectID.uriRepresentation()` of the indexed object. Stable
        /// across launches for saved objects, and the only handle persistent
        /// history offers for an object that has since been deleted.
        var objectURI: String
    }

    var version: Int = Self.currentVersion
    /// Sorted `NSPersistentStore.identifier`s (the store UUIDs) of the container
    /// the entries came from.
    var storeIdentity: [String]
    /// Archived `NSPersistentHistoryToken` current when `entries` were collected;
    /// `nil` for stores without history tracking (in-memory), which makes the
    /// snapshot unusable on purpose.
    var historyToken: Data?
    var entries: [Entry]
}

nonisolated enum SearchIndexSnapshotStore {
    private static let logger = Logger.app(category: "SearchIndexSnapshot")

    /// `Caches/SearchIndex/`. Caches is regenerable and excluded from backup,
    /// which is exactly what this file is.
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SearchIndex", isDirectory: true)
    }

    /// One file per store identity, so switching containers never overwrites
    /// another container's snapshot.
    static func url(in directory: URL, identity: [String]) -> URL {
        let digest = SHA256.hash(data: Data(identity.joined(separator: "|").utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("index-v\(SearchIndexSnapshot.currentVersion)-\(digest).json")
    }

    static func load(from url: URL) -> SearchIndexSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SearchIndexSnapshot.self, from: data)
        } catch {
            logger.warning("Ignoring unreadable search index snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func write(_ snapshot: SearchIndexSnapshot, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: the next launch just does a full pass again.
            logger.warning("Could not write search index snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Refresh

nonisolated struct SearchIndexRefreshOutcome: Sendable {
    let contents: SearchIndexContents
    let source: SearchIndexService.RefreshSource
}

extension SearchIndexService {

    /// Result of replaying persistent history over a snapshot's entries.
    nonisolated enum HistoryReplay: Sendable {
        /// Nothing searchable changed. `sawTransactions` is true when history
        /// held unrelated transactions, so the caller can advance the token.
        case unchanged(sawTransactions: Bool)
        case patched([SearchIndexSnapshot.Entry])
        /// The snapshot cannot be brought up to date; do a full pass.
        case fallback(reason: String)
    }

    /// Managed object class names of the entities the index covers, compared
    /// against `NSEntityDescription.managedObjectClassName` so no `+entity`
    /// lookup is needed (ambiguous under the two-store configuration).
    nonisolated static let searchableClassNames: Set<String> = Set(
        [CDStudent.self, CDLesson.self, CDNote.self, CDTodoItemEntity.self, CDWorkModel.self]
            .map { NSStringFromClass($0) }
    )

    // MARK: Container facts (cheap; read on the caller's actor)

    nonisolated static func storeIdentity(of container: NSPersistentContainer) -> [String] {
        container.persistentStoreCoordinator.persistentStores
            .compactMap(\.identifier)
            .sorted()
    }

    /// The coordinator's current history token, archived so it can cross
    /// isolation boundaries and live in the snapshot.
    nonisolated static func archivedCurrentHistoryToken(of container: NSPersistentContainer) -> Data? {
        guard let token = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil) else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private nonisolated static func unarchiveToken(_ data: Data) -> NSPersistentHistoryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    // MARK: Orchestration (off the main actor)

    /// Snapshot-first refresh. See the file header for the decision tree.
    @concurrent
    nonisolated static func refreshContents(
        context: NSManagedObjectContext,
        identity: [String],
        currentToken: Data?,
        snapshotDirectory: URL?,
        changeLimit: Int
    ) async -> SearchIndexRefreshOutcome {
        guard let snapshotDirectory else {
            return await fullRebuild(context: context, identity: identity, currentToken: currentToken, snapshotDirectory: nil)
        }
        let url = SearchIndexSnapshotStore.url(in: snapshotDirectory, identity: identity)

        guard let snapshot = SearchIndexSnapshotStore.load(from: url) else {
            logger.info("Search index: no snapshot for this store; full pass")
            return await fullRebuild(context: context, identity: identity, currentToken: currentToken, snapshotDirectory: snapshotDirectory)
        }
        guard snapshot.version == SearchIndexSnapshot.currentVersion, snapshot.storeIdentity == identity else {
            logger.info("Search index: snapshot is for another version or store; full pass")
            return await fullRebuild(context: context, identity: identity, currentToken: currentToken, snapshotDirectory: snapshotDirectory)
        }
        guard let snapshotToken = snapshot.historyToken else {
            logger.info("Search index: snapshot carries no history token; full pass")
            return await fullRebuild(context: context, identity: identity, currentToken: currentToken, snapshotDirectory: snapshotDirectory)
        }

        let entries = snapshot.entries
        let replay = await context.perform {
            replayHistory(since: snapshotToken, over: entries, context: context, changeLimit: changeLimit)
        }

        switch replay {
        case .unchanged(let sawTransactions):
            if sawTransactions {
                // Advance the token so the next launch does not re-read the same
                // unrelated transactions.
                var advanced = snapshot
                advanced.historyToken = currentToken ?? snapshot.historyToken
                SearchIndexSnapshotStore.write(advanced, to: url)
            }
            return SearchIndexRefreshOutcome(contents: buildContents(from: entries), source: .snapshot)

        case .patched(let patched):
            SearchIndexSnapshotStore.write(
                SearchIndexSnapshot(storeIdentity: identity, historyToken: currentToken, entries: patched),
                to: url
            )
            return SearchIndexRefreshOutcome(contents: buildContents(from: patched), source: .incremental)

        case .fallback(let reason):
            logger.info("Search index: \(reason, privacy: .public); full pass")
            return await fullRebuild(context: context, identity: identity, currentToken: currentToken, snapshotDirectory: snapshotDirectory)
        }
    }

    /// Full pass over every searchable entity, then a snapshot write.
    ///
    /// `currentToken` must have been read *before* this call so that a save
    /// landing during the pass is replayed next launch rather than lost.
    @concurrent
    nonisolated static func fullRebuild(
        context: NSManagedObjectContext,
        identity: [String],
        currentToken: Data?,
        snapshotDirectory: URL?
    ) async -> SearchIndexRefreshOutcome {
        let entries = await context.perform { collectAllEntries(context: context) }
        if let snapshotDirectory {
            SearchIndexSnapshotStore.write(
                SearchIndexSnapshot(storeIdentity: identity, historyToken: currentToken, entries: entries),
                to: SearchIndexSnapshotStore.url(in: snapshotDirectory, identity: identity)
            )
        }
        return SearchIndexRefreshOutcome(contents: buildContents(from: entries), source: .fullRebuild)
    }

    nonisolated static func buildContents(from entries: [SearchIndexSnapshot.Entry]) -> SearchIndexContents {
        var contents = SearchIndexContents()
        for entry in entries {
            contents.add(entry.result, text: entry.text)
        }
        return contents
    }

    // MARK: History replay (inside `context.perform`)

    private nonisolated static func replayHistory(
        since tokenData: Data,
        over entries: [SearchIndexSnapshot.Entry],
        context: NSManagedObjectContext,
        changeLimit: Int
    ) -> HistoryReplay {
        guard let token = unarchiveToken(tokenData) else {
            return .fallback(reason: "snapshot history token is unreadable")
        }

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        let transactions: [NSPersistentHistoryTransaction]
        do {
            let result = try context.execute(request) as? NSPersistentHistoryResult
            transactions = (result?.result as? [NSPersistentHistoryTransaction]) ?? []
        } catch {
            // Includes NSPersistentHistoryTokenExpiredError once old history is purged.
            return .fallback(reason: "history since snapshot is unavailable (\(error.localizedDescription))")
        }
        guard !transactions.isEmpty else { return .unchanged(sawTransactions: false) }

        // Net effect per object, in transaction order: a later delete wins over
        // an earlier insert/update and vice versa.
        var deleted = Set<String>()
        var touched: [String: NSManagedObjectID] = [:]
        for transaction in transactions {
            for change in transaction.changes ?? [] {
                let objectID = change.changedObjectID
                guard searchableClassNames.contains(objectID.entity.managedObjectClassName) else { continue }
                let uri = objectID.uriRepresentation().absoluteString
                switch change.changeType {
                case .delete:
                    touched.removeValue(forKey: uri)
                    deleted.insert(uri)
                case .insert, .update:
                    deleted.remove(uri)
                    touched[uri] = objectID
                @unknown default:
                    continue
                }
            }
        }
        guard !deleted.isEmpty || !touched.isEmpty else { return .unchanged(sawTransactions: true) }
        guard deleted.count + touched.count <= changeLimit else {
            return .fallback(reason: "\(deleted.count + touched.count) searchable changes exceed the incremental limit")
        }

        var byURI = Dictionary(entries.map { ($0.objectURI, $0) }, uniquingKeysWith: { _, latest in latest })
        for uri in deleted {
            byURI.removeValue(forKey: uri)
        }
        for (uri, objectID) in touched {
            if let object = try? context.existingObject(with: objectID), let entry = entry(for: object) {
                byURI[uri] = entry
            } else {
                // Deleted after the history was written, or no longer indexable.
                byURI.removeValue(forKey: uri)
            }
        }
        return .patched(Array(byURI.values))
    }

    // MARK: Collection (inside `context.perform`, or on a caller-owned context)

    nonisolated static func collectAllEntries(context: NSManagedObjectContext) -> [SearchIndexSnapshot.Entry] {
        var entries: [SearchIndexSnapshot.Entry] = []
        func collect<T: NSManagedObject>(_ type: T.Type) {
            for object in context.safeFetch(CDFetchRequest(type)) {
                if let entry = entry(for: object) {
                    entries.append(entry)
                }
            }
        }
        collect(CDStudent.self)
        collect(CDLesson.self)
        collect(CDNote.self)
        collect(CDTodoItemEntity.self)
        collect(CDWorkModel.self)
        return entries
    }

    /// The index entry for one managed object, or `nil` when the object is not
    /// searchable or has no id yet.
    nonisolated static func entry(for object: NSManagedObject) -> SearchIndexSnapshot.Entry? {
        let uri = object.objectID.uriRepresentation().absoluteString
        switch object {
        case let student as CDStudent:
            guard let id = student.id else { return nil }
            return .init(
                result: SearchResult(id: id, entityType: .student, title: student.fullName, snippet: student.level.rawValue),
                text: "\(student.firstName) \(student.lastName) \(student.nickname ?? "")",
                objectURI: uri
            )
        case let lesson as CDLesson:
            guard let id = lesson.id else { return nil }
            return .init(
                result: SearchResult(id: id, entityType: .lesson, title: lesson.name, snippet: lesson.area),
                text: "\(lesson.name) \(lesson.area) \(lesson.sequence) \(lesson.section)",
                objectURI: uri
            )
        case let note as CDNote:
            guard let id = note.id else { return nil }
            let tags = (note.tags as? [String]) ?? []
            let body = note.body
            return .init(
                result: SearchResult(
                    id: id, entityType: .note,
                    title: String(body.prefix(80)), snippet: tags.first ?? "", date: note.createdAt
                ),
                text: "\(body) \(tags.joined(separator: " "))",
                objectURI: uri
            )
        case let todo as CDTodoItemEntity:
            guard let id = todo.id else { return nil }
            return .init(
                result: SearchResult(id: id, entityType: .todo, title: todo.title, snippet: todo.notes, date: todo.createdAt),
                text: "\(todo.title) \(todo.notes)",
                objectURI: uri
            )
        case let work as CDWorkModel:
            guard let id = work.id else { return nil }
            return .init(
                result: SearchResult(
                    id: id, entityType: .work, title: work.title, snippet: work.status.rawValue, date: work.createdAt
                ),
                text: work.title,
                objectURI: uri
            )
        default:
            return nil
        }
    }
}
