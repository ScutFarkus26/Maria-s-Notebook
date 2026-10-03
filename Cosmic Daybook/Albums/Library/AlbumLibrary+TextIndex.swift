// AlbumLibrary+TextIndex.swift
// The page-text index: building it in the background, keeping its on-disk cache,
// and reading it back for search.

import Foundation

extension AlbumLibrary {

    func rebuildIndex() {
        guard !indexing else { return }
        indexPurged = false
        pageTexts = [:]
        folds.dropAll()
        if let dir = Self.indexCacheDirectory() {
            try? FileManager.default.removeItem(at: dir)
        }
        startIndexBuild()
    }

    func buildIndexes(policy: EnergyPolicy = .shared) async {
        guard !indexing else { return }
        indexing = true
        indexProgress = 0
        indexedPageCount = 0
        var lastSeen = (UserDefaults.standard.dictionary(forKey: Self.lastSeenKey) as? [String: Double]) ?? [:]
        var lastSeenChanged = false
        let items = albums.map { (id: $0.id, url: $0.url, pages: $0.pageCount) }
        let cacheDir = Self.indexCacheDirectory()
        for (i, item) in items.enumerated() {
            // Parsing a PDF is discretionary work, so a hot device or Low Power
            // Mode pauses between albums rather than abandoning the index.
            if i > 0 {
                await pauseIndexingWhileDeferred(policy: policy)
            }
            let modified = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            // Indexing is background maintenance, not something the guide is waiting on:
            // `.utility` keeps the PDF text extraction off the cores the UI needs.
            let texts = await Task.detached(priority: .utility) {
                Self.loadOrBuildIndex(url: item.url, modified: modified, cacheDir: cacheDir)
            }.value
            pageTexts[item.id] = texts
            // Folded on first search; a changed album's fold of its old text goes.
            if modDates[item.id] != modified { folds.drop(albumID: item.id) }
            modDates[item.id] = modified
            if let seen = lastSeen[item.id] {
                if modified.timeIntervalSinceReferenceDate > seen + 1 {
                    updatedAlbumIDs.insert(item.id)
                }
            } else {
                // First sighting of this album — record it without a badge.
                lastSeen[item.id] = modified.timeIntervalSinceReferenceDate
                lastSeenChanged = true
            }
            indexedPageCount += texts.count
            indexProgress = Double(i + 1) / Double(max(items.count, 1))
            // Give the main actor a turn between albums so a long shelf does not
            // monopolise it with the per-album bookkeeping above.
            await Task.yield()
        }
        if lastSeenChanged {
            UserDefaults.standard.set(lastSeen, forKey: Self.lastSeenKey)
        }
        indexing = false
        indexPurged = false
        // Embedding every lesson is discretionary work too.
        await pauseIndexingWhileDeferred(policy: policy)
        await semantic.build(items: semanticItems())
    }

    /// Waits while the device is too hot (or in Low Power Mode) to index the
    /// next album — for as long as that lasts, without polling. It never gives
    /// up and runs hot on its own; only a caller awaiting the index
    /// (`ensureIndexed()`, i.e. the guide or a tool asked for it) or
    /// cancellation ends the wait early. Returns whether it waited (1) or not
    /// (0); the app ignores it, the tests read it.
    @discardableResult
    func pauseIndexingWhileDeferred(policy: EnergyPolicy) async -> Int {
        guard policy.shouldDeferMaintenance, !indexingDemanded, !Task.isCancelled else { return 0 }
        let wait = Task { await policy.waitUntilMaintenanceAllowed() }
        indexEnergyWait = wait
        await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            wait.cancel()
        }
        indexEnergyWait = nil
        return 1
    }

    /// Per-lesson titles and body texts used to build the semantic index.
    private func semanticItems() -> [AlbumSemanticIndex.BuildItem] {
        albums.map { album in
            let texts = pageTexts[album.id] ?? []
            let bodies = album.lessons.enumerated().map { i, lesson in
                let end = i + 1 < album.lessons.count
                    ? max(album.lessons[i + 1].pageIndex, lesson.pageIndex + 1)
                    : album.pageCount
                let body = (lesson.pageIndex..<min(end, texts.count))
                    .map { texts[$0] }
                    .joined(separator: " ")
                return lesson.title + ". " + String(body.prefix(700))
            }
            return AlbumSemanticIndex.BuildItem(id: album.id, modified: modDates[album.id] ?? .distantPast,
                                                titles: album.lessons.map(\.title), bodies: bodies)
        }
    }

    var indexReady: Bool { !indexing && !indexPurged && !pageTexts.isEmpty }

    func text(albumID: String, pageIndex: Int) -> String? {
        guard let pages = pageTexts[albumID], pages.indices.contains(pageIndex) else { return nil }
        return pages[pageIndex]
    }

    /// Every album's page text with its fold, for a search. An album whose fold
    /// a load, a trim or a change left missing is folded off the main actor
    /// (`AlbumTextFolds`), so the first search after one no longer stalls it.
    func corpus() async -> AlbumSearchCorpus {
        let albums = self.albums
        let pages = await folds.pages(for: albums.map { (id: $0.id, texts: pageTexts[$0.id] ?? []) })
        return AlbumSearchCorpus(albums: zip(albums, pages).map { album, pages in
            AlbumSearchCorpus.AlbumData(id: album.id, title: album.title, subject: album.subject,
                                        lessons: album.lessons, texts: pages.texts, folded: pages.folded)
        })
    }

    nonisolated private struct CachedIndex: Codable {
        let modified: Date
        let pageTexts: [String]
    }

    /// The album's page text, from the cache or the PDF; a search folds it later.
    nonisolated static func loadOrBuildIndex(url: URL, modified: Date, cacheDir: URL?) -> [String] {
        let cacheURL = cacheDir?.appendingPathComponent(url.lastPathComponent + ".index.json")
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedIndex.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1 {
            return cached.pageTexts
        }
        let texts = AlbumPageTextReader.pageTexts(url: url)
        if let cacheURL,
           let data = try? JSONEncoder().encode(CachedIndex(modified: modified, pageTexts: texts)) {
            try? data.write(to: cacheURL)
        }
        return texts
    }
}
