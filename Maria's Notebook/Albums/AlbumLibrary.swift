// AlbumLibrary.swift
// The content layer. Album wraps one PDF: its outline (parsed into lesson
// references), cover rendering, and highlight annotations. AlbumLibrary
// owns the set of album folders (security-scoped bookmarks), the full-text
// page index (built in the background, cached per file modification date),
// change detection for "Updated" badges, and the semantic index build.

import CoreData
import SwiftUI
import PDFKit

// PlatformImage comes from Utils/PrintUtils.swift; PlatformColor from
// Services/ReportGeneratorService.swift.

// MARK: - Album

@Observable @MainActor
final class Album: Identifiable {
    let id: String            // filename, e.g. "Biology Album.pdf"
    let url: URL
    let title: String
    let subject: AlbumSubject
    let document: PDFDocument
    let pageCount: Int
    let outline: [AlbumOutlineNode]
    let lessons: [AlbumLessonRef]  // flattened outline in document order
    var cover: PlatformImage?
    var coverRequested = false

    @ObservationIgnored private var cachedFingerprint: String?

    /// Content fingerprint, used to recognise this album again after the PDF
    /// is renamed or moved. Computed once — the document is already open and
    /// the outline already parsed by the time anything asks for it.
    var fingerprint: String {
        if let cachedFingerprint { return cachedFingerprint }
        let value = AlbumIdentityRepair.fingerprint(
            pageCount: pageCount,
            lessonTitles: lessons.map(\.title),
            firstPageText: document.page(at: 0)?.string ?? "")
        cachedFingerprint = value
        return value
    }

    init?(url: URL) {
        guard let document = PDFDocument(url: url) else { return nil }
        self.id = url.lastPathComponent
        self.url = url
        self.title = Album.cleanTitle(from: url)
        self.subject = AlbumSubject.detect(from: title)
        self.document = document
        self.pageCount = document.pageCount

        var nodes: [AlbumOutlineNode] = []
        var flat: [AlbumLessonRef] = []
        if let root = document.outlineRoot {
            Album.parse(outline: root, document: document, depth: 0, path: "r",
                        into: &nodes, flat: &flat)
        }
        self.outline = nodes
        self.lessons = flat.sorted { $0.pageIndex == $1.pageIndex ? $0.depth < $1.depth : $0.pageIndex < $1.pageIndex }
    }

    static func cleanTitle(from url: URL) -> String {
        var t = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: " Album", with: "")
            .trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? url.deletingPathExtension().lastPathComponent : t
    }

    private static func parse(outline: PDFOutline, document: PDFDocument, depth: Int, path: String,
                              into nodes: inout [AlbumOutlineNode], flat: inout [AlbumLessonRef]) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let title = (child.label ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            var pageIndex = 0
            if let page = child.destination?.page { pageIndex = document.index(for: page) }
            let nodePath = "\(path).\(i)"
            var node = AlbumOutlineNode(id: nodePath, title: title, pageIndex: pageIndex, children: nil)
            flat.append(AlbumLessonRef(title: title, pageIndex: pageIndex, depth: depth))
            if child.numberOfChildren > 0 {
                var sub: [AlbumOutlineNode] = []
                parse(outline: child, document: document, depth: depth + 1, path: nodePath,
                      into: &sub, flat: &flat)
                node.children = sub
            }
            nodes.append(node)
        }
    }

    /// Number of leaf outline entries — a decent proxy for "lessons".
    var lessonCount: Int {
        func leaves(_ nodes: [AlbumOutlineNode]) -> Int {
            nodes.reduce(0) { $0 + (($1.children?.isEmpty ?? true) ? 1 : leaves($1.children!)) }
        }
        return leaves(outline)
    }

    /// The deepest outline entry at or before the given page.
    func lesson(forPage pageIndex: Int) -> AlbumLessonRef? {
        lessons.last { $0.pageIndex <= pageIndex }
    }

    /// The page range covered by the lesson segment containing `pageIndex`
    /// (from its outline entry to the next outline entry in document order).
    func lessonRange(forPage pageIndex: Int) -> ClosedRange<Int> {
        guard let current = lesson(forPage: pageIndex) else { return pageIndex...pageIndex }
        let next = lessons.first { $0.pageIndex > current.pageIndex }
        let end = (next?.pageIndex).map { max(current.pageIndex, $0 - 1) } ?? (pageCount - 1)
        return current.pageIndex...min(end, pageCount - 1)
    }

    // MARK: CDAlbumHighlight rendering

    /// Annotations we've injected into the in-memory document (never written
    /// back to the PDF file), so they can be cleanly replaced.
    private var appliedHighlightAnnotations: [(annotation: PDFAnnotation, page: PDFPage)] = []

    func applyHighlights(_ items: [CDAlbumHighlight]) {
        for entry in appliedHighlightAnnotations {
            entry.page.removeAnnotation(entry.annotation)
        }
        appliedHighlightAnnotations = []
        for item in items {
            guard let page = document.page(at: Int(item.pageIndex)) else { continue }
            for rect in item.rects {
                let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.color = Album.highlightColor(item.colorName).withAlphaComponent(0.45)
                let local = [CGPoint(x: 0, y: rect.height),
                             CGPoint(x: rect.width, y: rect.height),
                             CGPoint(x: 0, y: 0),
                             CGPoint(x: rect.width, y: 0)]
                #if os(macOS)
                annotation.quadrilateralPoints = local.map { NSValue(point: $0) }
                #else
                annotation.quadrilateralPoints = local.map { NSValue(cgPoint: $0) }
                #endif
                page.addAnnotation(annotation)
                appliedHighlightAnnotations.append((annotation, page))
            }
        }
    }

    static func highlightColor(_ name: String) -> PlatformColor {
        switch name {
        case "green": .systemGreen
        case "blue": .systemBlue
        case "pink": .systemPink
        default: .systemYellow
        }
    }

    nonisolated static func renderCoverData(url: URL) -> Data? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: 420, height: 560)
        let image = page.thumbnail(of: size, for: .mediaBox)
        #if os(macOS)
        return image.tiffRepresentation
        #else
        return image.pngData()
        #endif
    }
}

// MARK: - Library

@Observable @MainActor
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
    /// Albums whose PDF changed since the user last opened them.
    var updatedAlbumIDs: Set<String> = []
    /// Set after each load; the Albums surface clears it by running
    /// `repairAlbumIdentities(in:)`, which needs a managed object context.
    private(set) var needsIdentityRepair = false
    let semantic = AlbumSemanticIndex()

    // The three index caches below are `internal` rather than `private` only so
    // `AlbumLibrary+MemoryPressure.swift` can release them. Nothing else should
    // touch them — read page text through `text(albumID:pageIndex:)` or `corpus()`.

    /// Per-album page text, keyed by album id.
    var pageTexts: [String: [String]] = [:]
    /// Case- and diacritic-folded copy of `pageTexts`, used for matching. Purely
    /// derived, so memory pressure drops it and `folded(for:)` rebuilds per album
    /// on the next search.
    var foldedTexts: [String: [String]] = [:]
    /// Modification date of each album's file at the time it was indexed.
    private var modDates: [String: Date] = [:]
    /// Set when critical memory pressure purged `pageTexts`. The on-disk index
    /// cache still holds every album's extracted text, so recovering is a JSON
    /// decode rather than a PDF re-extraction — but nothing may search until
    /// `buildIndexes()` has run again.
    var indexPurged = false

    static let bookmarksKey = UserDefaultsKeys.albumsFolderBookmarks
    static let lastSeenKey = UserDefaultsKeys.albumsLastSeenModDates

    var folderURL: URL? { folderURLs.first }

    func album(id: String) -> Album? { albums.first { $0.id == id } }

    private init() {
        observeMemoryPressure()
    }

    // MARK: Folder access

    func bootstrap() {
        let bookmarkList = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data]) ?? []
        let resolved = bookmarkList.compactMap { resolveBookmark($0) }
        if !resolved.isEmpty {
            load(from: resolved)
            return
        }
        state = .needsFolder
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
    func ensureIndexed() async {
        bootstrapIfNeeded()
        while indexing || state == .loading {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Memory pressure can drop the page-text index after a successful load.
        // Rebuild it here rather than leaving callers with an empty corpus.
        if indexPurged, state == .ready {
            await buildIndexes()
        }
    }

    /// Adds a folder to the library (the first chosen folder just loads it).
    func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            #if os(macOS)
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let data = try url.bookmarkData(options: .minimalBookmark,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
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
        load(from: resolved)
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
        if resolved.isEmpty {
            albums = []
            folderURLs = []
            state = .needsFolder
        } else {
            load(from: resolved)
        }
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        #if os(macOS)
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        #else
        guard let url = try? URL(resolvingBookmarkData: data,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        #endif
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    // MARK: Loading

    func load(from folders: [URL]) {
        state = .loading
        folderURLs = folders
        var pdfURLs: [URL] = []
        var seenNames = Set<String>()
        for folder in folders {
            let contents = (try? FileManager.default
                .contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension.lowercased() == "pdf" }) ?? []
            for url in contents where !seenNames.contains(url.lastPathComponent) {
                seenNames.insert(url.lastPathComponent)
                pdfURLs.append(url)
            }
        }
        pdfURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !pdfURLs.isEmpty else {
            state = .failed("No PDF files were found in the chosen folder. "
                + "Choose a folder that contains your album PDFs.")
            return
        }
        albums = pdfURLs.compactMap { Album(url: $0) }
        state = .ready
        needsIdentityRepair = true
        Task { await buildIndexes() }
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
        let onDisk = Set(folderURLs.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .map(\.lastPathComponent)
        })
        if changed || fileNames != onDisk {
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
        AlbumIdentityRepair.repairRenamedAlbums(albums, in: context)
        // A revised PDF can shift pagination under existing lesson links.
        // The outline title is the anchor, so they re-point themselves.
        for album in albums {
            LessonAlbumMatcher.reresolvePages(in: album, context: context)
        }
    }

    // MARK: Text index

    func rebuildIndex() {
        guard !indexing else { return }
        indexPurged = false
        pageTexts = [:]
        foldedTexts = [:]
        if let dir = Self.indexCacheDirectory() {
            try? FileManager.default.removeItem(at: dir)
        }
        Task { await buildIndexes() }
    }

    func buildIndexes() async {
        guard !indexing else { return }
        indexing = true
        indexProgress = 0
        indexedPageCount = 0
        var lastSeen = (UserDefaults.standard.dictionary(forKey: Self.lastSeenKey) as? [String: Double]) ?? [:]
        var lastSeenChanged = false
        let items = albums.map { (id: $0.id, url: $0.url, pages: $0.pageCount) }
        let cacheDir = Self.indexCacheDirectory()
        for (i, item) in items.enumerated() {
            let modified = (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let result = await Task.detached(priority: .userInitiated) {
                Self.loadOrBuildIndex(url: item.url, modified: modified, cacheDir: cacheDir)
            }.value
            pageTexts[item.id] = result.texts
            foldedTexts[item.id] = result.folded
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
            indexedPageCount += result.texts.count
            indexProgress = Double(i + 1) / Double(max(items.count, 1))
        }
        if lastSeenChanged {
            UserDefaults.standard.set(lastSeen, forKey: Self.lastSeenKey)
        }
        indexing = false
        indexPurged = false
        await semantic.build(items: semanticItems())
    }

    /// Per-lesson titles and body texts used to build the semantic index.
    private func semanticItems() -> [(id: String, modified: Date, titles: [String], bodies: [String])] {
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
            return (album.id, modDates[album.id] ?? .distantPast,
                    album.lessons.map(\.title), bodies)
        }
    }

    var indexReady: Bool { !indexing && !indexPurged && !pageTexts.isEmpty }

    func text(albumID: String, pageIndex: Int) -> String? {
        guard let pages = pageTexts[albumID], pages.indices.contains(pageIndex) else { return nil }
        return pages[pageIndex]
    }

    /// Folded text for one album, rebuilt from `pageTexts` if memory pressure
    /// dropped it. Folding a single album's pages is far cheaper than keeping a
    /// second full copy of the corpus resident for the life of the app.
    private func folded(for albumID: String) -> [String] {
        if let cached = foldedTexts[albumID] { return cached }
        guard let texts = pageTexts[albumID] else { return [] }
        let built = texts.map(Self.fold)
        foldedTexts[albumID] = built
        return built
    }

    func corpus() -> AlbumSearchCorpus {
        AlbumSearchCorpus(albums: albums.map {
            AlbumSearchCorpus.AlbumData(id: $0.id, title: $0.title, subject: $0.subject,
                                   lessons: $0.lessons,
                                   texts: pageTexts[$0.id] ?? [],
                                   folded: folded(for: $0.id))
        })
    }

    // MARK: Covers

    func loadCoverIfNeeded(_ album: Album) {
        guard album.cover == nil, !album.coverRequested else { return }
        album.coverRequested = true
        let url = album.url
        Task {
            let data = await Task.detached(priority: .utility) {
                Album.renderCoverData(url: url)
            }.value
            if let data, let image = PlatformImage(data: data) {
                album.cover = image
            }
        }
    }

    // MARK: Background helpers

    nonisolated private struct CachedIndex: Codable {
        let modified: Date
        let pageTexts: [String]
    }

    nonisolated static func indexCacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AlbumSearchIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func loadOrBuildIndex(url: URL, modified: Date, cacheDir: URL?)
        -> (texts: [String], folded: [String]) {
        let cacheURL = cacheDir?.appendingPathComponent(url.lastPathComponent + ".index.json")
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedIndex.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1 {
            return (cached.pageTexts, cached.pageTexts.map(fold))
        }
        var texts: [String] = []
        if let doc = PDFDocument(url: url) {
            for i in 0..<doc.pageCount {
                let raw = doc.page(at: i)?.string ?? ""
                texts.append(normalize(raw))
            }
        }
        if let cacheURL,
           let data = try? JSONEncoder().encode(CachedIndex(modified: modified, pageTexts: texts)) {
            try? data.write(to: cacheURL)
        }
        return (texts, texts.map(fold))
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

    nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
