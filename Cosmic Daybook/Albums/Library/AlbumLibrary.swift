// AlbumLibrary.swift
// The content layer. AlbumLibrary owns the set of album folders
// (security-scoped bookmarks), the full-text page index (built in the
// background, cached per file modification date), change detection for
// "Updated" badges, and the semantic index build. Album, the model for one
// PDF, is in Album.swift.

import CoreData
import SwiftUI
import PDFKit

// MARK: - Library

@Observable
final class AlbumLibrary {
    /// App-lifetime library. The album corpus is the guide's own reference
    /// shelf, not classroom data, so it does not swap with the active
    /// classroom the way `AppDependencies` services do.
    static let shared = AlbumLibrary()

    enum State: Equatable { case needsFolder, loading, ready, failed(String) }

    var state: State = .needsFolder
    var albums: [Album] = []
    var indexing = false
    var indexProgress: Double = 0
    var indexedPageCount = 0
    private(set) var folderURLs: [URL] = []
    /// The iCloud album shelf (`AlbumICloudShelf`) as of the last load; nil
    /// when iCloud Drive is off. Always searched first, without a bookmark.
    private(set) var shelfURL: URL?
    /// Albums on the shelf still downloading to this device.
    var pendingShelfAlbumNames: Set<String> = []
    /// Albums being copied onto the shelf now.
    var albumsBeingKept: Set<String> = []
    /// The last shelf action's failure, for an alert; cleared by the view.
    var shelfError: String?
    /// The download of pending shelf albums in flight (`AlbumLibrary+ICloudShelf`).
    @ObservationIgnored var shelfDownloadTask: Task<Void, Never>?
    /// Albums whose PDF changed since the user last opened them.
    var updatedAlbumIDs: Set<String> = []
    /// Set after each load; the Albums surface clears it by running
    /// `repairAlbumIdentities(in:)`, which needs a managed object context.
    private(set) var needsIdentityRepair = false
    let semantic = AlbumSemanticIndex()

    // The index caches below are `internal` rather than `private` only so
    // `AlbumLibrary+MemoryPressure.swift` can release them. Nothing else should
    // touch them — read page text through `text(albumID:pageIndex:)` or `corpus()`.

    /// Per-album page text, keyed by album id.
    var pageTexts: [String: [String]] = [:]
    /// The case- and diacritic-folded copy of `pageTexts` that search matches
    /// against, folded off the main actor by the first search that needs it.
    let folds = AlbumTextFolds()
    /// Modification date of each album's file at the time it was indexed.
    var modDates: [String: Date] = [:]
    /// Set when critical memory pressure purged `pageTexts`. The on-disk index
    /// cache still holds every album's extracted text, so recovering is a JSON
    /// decode rather than a PDF re-extraction — but nothing may search until
    /// `buildIndexes()` has run again.
    var indexPurged = false
    /// The index build in flight, cleared when it finishes. `ensureIndexed()`
    /// awaits it instead of polling `indexing`; a build queued while another
    /// runs is dropped, as `buildIndexes()` would have declined it anyway.
    private var indexTask: Task<Void, Never>?

    static let bookmarksKey = UserDefaultsKeys.albumsFolderBookmarks
    static let lastSeenKey = UserDefaultsKeys.albumsLastSeenModDates

    func album(id: String) -> Album? { albums.first { $0.id == id } }

    private init() {
        observeMemoryPressure()
    }

    // MARK: Folder access

    func bootstrap() {
        let bookmarkList = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data]) ?? []
        let resolved = bookmarkList.compactMap { resolveBookmark($0) }
        let folders = withShelf(resolved)
        if !resolved.isEmpty || folders.count > resolved.count {
            load(from: folders)
            return
        }
        state = .needsFolder
    }

    /// True when this device can reach at least one album folder: a registered
    /// bookmark that still resolves, or an iCloud shelf with albums on it. The
    /// backup restore asks this without loading the library so it can tell the
    /// guide when restored annotations have no shelf yet.
    static func hasResolvableFolderBookmark() -> Bool {
        let bookmarkList = (UserDefaults.standard.array(forKey: bookmarksKey) as? [Data]) ?? []
        let bookmarked = bookmarkList.contains { data in
            (try? SecurityScopedBookmark.resolve(data)) != nil
        }
        return bookmarked || shelfHasAlbums(AlbumICloudShelf.directory())
    }

    /// Re-reads the folder bookmarks and fingerprint map after a backup restore
    /// has applied preferences. A library that never loaded stays lazy; one that
    /// already showed a shelf (or "needs folder") reloads so the restored
    /// annotations reattach without a relaunch.
    func reloadAfterRestore() {
        guard didBootstrap else { return }
        bootstrap()
    }

    /// Opening the albums means parsing every PDF and indexing its text, so
    /// the library loads the first time the Albums section (or an AI tool)
    /// actually needs it rather than at app launch.
    private var didBootstrap = false

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        bootstrap()
    }

    /// Waits until the page-text and semantic indexes are usable. Callers
    /// outside the UI (the chat and MCP album tools) use this instead of
    /// assuming the guide has already visited the Albums section.
    ///
    /// `load(from:)` runs to completion on the main actor, so `.loading` is
    /// never observable across a suspension here; only the index build is.
    func ensureIndexed() async {
        bootstrapIfNeeded()
        // Someone is waiting on the index now, so it is no longer
        // discretionary: a build paused for heat carries on.
        demandIndexing()
        await awaitIndexBuild()
        // Memory pressure can drop the page-text index after a successful load.
        // Rebuild it here rather than leaving callers with an empty corpus.
        if indexPurged, state == .ready {
            startIndexBuild()
            demandIndexing()
            await awaitIndexBuild()
        }
    }

    /// Waits for the current build and any that replaces it meanwhile.
    private func awaitIndexBuild() async {
        while let task = indexTask {
            await task.value
        }
    }

    /// Runs `buildIndexes()` as the stored in-flight build, unless one is
    /// already stored.
    func startIndexBuild() {
        guard indexTask == nil else { return }
        indexTask = Task {
            await buildIndexes()
            indexTask = nil
            indexingDemanded = false
        }
    }

    /// A caller is awaiting the index (`ensureIndexed()`), so the build in
    /// flight stops waiting for the device to cool.
    @ObservationIgnored private(set) var indexingDemanded = false

    /// The energy wait the build is suspended in, if any.
    @ObservationIgnored var indexEnergyWait: Task<Void, Never>?

    /// Marks the index as needed now and releases a build paused for heat.
    func demandIndexing() {
        // Only a build in flight can be waiting; a demand with none running
        // must not leave the next discretionary build ungated.
        guard indexTask != nil else { return }
        indexingDemanded = true
        indexEnergyWait?.cancel()
    }

    /// Adds a folder to the library (the first chosen folder just loads it).
    func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try SecurityScopedBookmark.make(for: url, unscopedOptions: .minimalBookmark)
            var list = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data]) ?? []
            list.append(data)
            UserDefaults.standard.set(list, forKey: Self.bookmarksKey)
        } catch {
            // We can still use the folder for this session even if bookmarking failed.
        }
        let bookmarkList = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data]) ?? []
        var resolved: [URL] = []
        var seen = Set<String>()
        var deduped: [Data] = []
        for data in bookmarkList {
            guard let folder = resolveBookmark(data) else { continue }
            let path = folder.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            deduped.append(data)
            resolved.append(folder)
        }
        UserDefaults.standard.set(deduped, forKey: Self.bookmarksKey)
        if resolved.isEmpty {
            _ = url.startAccessingSecurityScopedResource()
            resolved = [url]
        }
        load(from: withShelf(resolved))
    }

    func removeFolder(_ url: URL) {
        let target = url.standardizedFileURL.path
        let bookmarkList = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data]) ?? []
        let kept = bookmarkList.filter { data in
            guard let folder = resolveBookmark(data) else { return false }
            return folder.standardizedFileURL.path != target
        }
        UserDefaults.standard.set(kept, forKey: Self.bookmarksKey)
        let resolved = kept.compactMap { resolveBookmark($0) }
        let folders = withShelf(resolved)
        if resolved.isEmpty, folders.isEmpty {
            albums = []
            folderURLs = []
            state = .needsFolder
        } else {
            load(from: folders)
        }
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        guard let url = try? SecurityScopedBookmark.resolve(data).url else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    // MARK: Loading

    /// Loads every album in `folders`, the first folder winning a filename
    /// two share (the iCloud shelf is first; see `withShelf`). An album still
    /// downloading from iCloud is left out and fetched in the background; the
    /// library reloads once it arrives (`AlbumLibrary+ICloudShelf`).
    func load(from folders: [URL]) {
        state = .loading
        folderURLs = folders
        let shelfPath = AlbumICloudShelf.directory()?.standardizedFileURL.path
        shelfURL = folders.first { $0.standardizedFileURL.path == shelfPath }
        var pdfURLs: [URL] = []
        var pending: [URL] = []
        var seenNames = Set<String>()
        for folder in folders {
            let listing = AlbumICloudShelf.listing(of: folder)
            for url in listing.ready where !seenNames.contains(url.lastPathComponent) {
                seenNames.insert(url.lastPathComponent)
                pdfURLs.append(url)
            }
            pending += listing.pending
        }
        pending.removeAll { seenNames.contains($0.lastPathComponent) }
        pendingShelfAlbumNames = Set(pending.map(\.lastPathComponent))
        downloadPendingAlbums(pending)
        pdfURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if pdfURLs.isEmpty, !pending.isEmpty {
            // Everything is still on its way from iCloud; the download reloads.
            return
        }
        guard !pdfURLs.isEmpty else {
            state = .failed("No PDF files were found in the chosen folder. "
                + "Choose a folder that contains your album PDFs.")
            return
        }
        albums = pdfURLs.compactMap { Album(url: $0) }
        state = .ready
        needsIdentityRepair = true
        startIndexBuild()
    }

    /// Re-checks every album file's modification date; if any changed on
    /// disk, reloads and re-indexes. Called when the app becomes active.
    func refreshIfChanged() {
        guard state == .ready, !indexing else { return }
        let changed = albums.contains { album in
            let current = (try? album.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let indexed = modDates[album.id] ?? .distantPast
            return abs(current.timeIntervalSince(indexed)) >= 1
        }
        let fileNames = Set(albums.map(\.id))
        let listings = folderURLs.map(AlbumICloudShelf.listing(of:))
        let onDisk = Set(listings.flatMap(\.ready).map(\.lastPathComponent))
        let pending = Set(listings.flatMap(\.pending).map(\.lastPathComponent)).subtracting(onDisk)
        // A new album on the shelf, or one another device added, joins too.
        if changed || fileNames != onDisk || pending != pendingShelfAlbumNames {
            load(from: folderURLs)
        }
    }

    /// The user opened this album — clear its "updated" badge.
    func markSeen(_ album: Album) {
        updatedAlbumIDs.remove(album.id)
        // `modDates` is only populated once indexing reaches this album, and
        // the guide can open it before then. Fall back to the file's own
        // modification date so the badge doesn't come back on next launch.
        let date = modDates[album.id]
            ?? (try? album.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        guard let date else { return }
        var lastSeen = (UserDefaults.standard.dictionary(forKey: Self.lastSeenKey) as? [String: Double]) ?? [:]
        lastSeen[album.id] = date.timeIntervalSinceReferenceDate
        UserDefaults.standard.set(lastSeen, forKey: Self.lastSeenKey)
    }

    // MARK: Identity repair

    /// Carries the guide's annotations across when an album PDF has been
    /// renamed or moved since the last load. Driven from the Albums surface
    /// because it needs a managed object context, which the library — being
    /// app-lifetime and classroom-independent — deliberately doesn't hold.
    func repairAlbumIdentities(in context: NSManagedObjectContext) {
        guard needsIdentityRepair, state == .ready else { return }
        needsIdentityRepair = false
        // Albums still on their way (or being copied onto the shelf) hold the
        // rename check back; the load their arrival starts runs it again.
        AlbumIdentityRepair.repairRenamedAlbums(
            albums, pendingNames: pendingShelfAlbumNames.union(albumsBeingKept), in: context
        )
        // A revised PDF can shift pagination under existing lesson links.
        // The outline title is the anchor, so they re-point themselves.
        for album in albums {
            LessonAlbumMatcher.reresolvePages(in: album, context: context)
        }
    }

    // MARK: Covers

    func loadCoverIfNeeded(_ album: Album) {
        guard album.cover == nil, !album.coverRequested else { return }
        album.coverRequested = true
        let url = album.url
        Task {
            let bitmap = await Task.detached(priority: .utility) {
                Album.renderCover(url: url)
            }.value
            if let bitmap {
                album.cover = Album.coverImage(from: bitmap)
            }
        }
    }

    // MARK: Background helpers

    nonisolated static func indexCacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AlbumSearchIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Normalizes extracted PDF text for display and searching:
    /// expands ligatures and smart quotes so plain typed queries match.
    nonisolated static func normalize(_ s: String) -> String {
        var t = s
        let replacements: [(String, String)] = [
            ("\u{FB00}", "ff"), ("\u{FB01}", "fi"), ("\u{FB02}", "fl"),
            ("\u{FB03}", "ffi"), ("\u{FB04}", "ffl"),
            ("\u{2018}", "'"), ("\u{2019}", "'"),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{00A0}", " ")
        ]
        for (from, to) in replacements {
            t = t.replacingOccurrences(of: from, with: to)
        }
        return t
    }
}
