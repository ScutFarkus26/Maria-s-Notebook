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

    /// Reads every album's page text, then embeds every lesson. A load that
    /// replaces the album list while this runs (a shelf download landing, a
    /// folder added) sends it round again for the new list, and critical memory
    /// pressure ends it with the index marked purged: either way the semantic
    /// build is never handed a text table that doesn't match the albums.
    func buildIndexes(policy: EnergyPolicy = .shared) async {
        guard !indexing else {
            // Another pass is reading the albums now; it goes round once more.
            indexBuildStale = true
            return
        }
        repeat {
            indexBuildStale = false
            guard let read = await indexPageTexts(policy: policy) else { continue }
            // Embedding every lesson is discretionary work too.
            await pauseIndexingWhileDeferred(policy: policy)
            if !isCurrentAlbumList(read) { indexBuildStale = true }
            guard !indexBuildStale, !indexPurged else { continue }
            await semantic.build(items: semanticItems())
        } while indexBuildStale && !Task.isCancelled
    }

    /// One pass over the album list as it stands. Returns the albums it read,
    /// or nil when a memory purge or a new album list cut it short; a new list
    /// marks the build stale so it goes round again.
    private func indexPageTexts(policy: EnergyPolicy) async -> [Album]? {
        indexing = true
        indexPurged = false
        indexProgress = 0
        indexedPageCount = 0
        defer { indexing = false }
        var lastSeen = (UserDefaults.standard.dictionary(forKey: Self.lastSeenKey) as? [String: Double]) ?? [:]
        var lastSeenChanged = false
        let read = albums
        let items = read.map { (id: $0.id, url: $0.url) }
        let cacheDir = Self.indexCacheDirectory()
        var cutShort = false
        for (i, item) in items.enumerated() {
            // Parsing a PDF is discretionary work, so a hot device or Low Power
            // Mode pauses between albums rather than abandoning the index.
            if i > 0 {
                await pauseIndexingWhileDeferred(policy: policy)
            }
            // A purge or a reload during the pause makes the rest of this pass moot.
            if indexPurged || indexBuildStale || !isCurrentAlbumList(read) {
                cutShort = true
                break
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
        if !indexPurged, !isCurrentAlbumList(read) { indexBuildStale = true }
        guard !cutShort, !indexPurged, !indexBuildStale else { return nil }
        return read
    }

    /// True while `albums` is still the list `read` was taken from: a load
    /// replaces every `Album`, even one whose file is unchanged.
    private func isCurrentAlbumList(_ read: [Album]) -> Bool {
        read.count == albums.count && zip(read, albums).allSatisfy { $0 === $1 }
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

    /// Per-lesson titles and body texts used to build the semantic index. An
    /// album whose page text hasn't been read yet waits for the next build, and
    /// a lesson's pages are clamped to the text there is.
    private func semanticItems() -> [AlbumSemanticIndex.BuildItem] {
        albums.compactMap { album in
            guard let texts = pageTexts[album.id] else { return nil }
            let bodies = album.lessons.enumerated().map { i, lesson in
                let end = i + 1 < album.lessons.count
                    ? max(album.lessons[i + 1].pageIndex, lesson.pageIndex + 1)
                    : album.pageCount
                let upper = min(end, texts.count)
                let body = (min(lesson.pageIndex, upper)..<upper)
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
