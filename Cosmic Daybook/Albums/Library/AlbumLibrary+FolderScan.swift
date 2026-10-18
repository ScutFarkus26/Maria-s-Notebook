// AlbumLibrary+FolderScan.swift
// One pass over the album folders: what to open, what is still in iCloud, and
// which chosen folders hold a newer copy of an album kept there; and the
// check on activation that runs it.

import Foundation

extension AlbumLibrary {

    /// Re-checks every album file's modification date; if any changed on
    /// disk, reloads and re-indexes. Called when the app becomes active.
    func refreshIfChanged() {
        switch state {
        case .needsFolder, .failed:
            // Nothing to open last time (or the shelf couldn't download):
            // another device may have kept albums in iCloud since. The same
            // albums still waiting are tried again quietly instead, so the
            // failure stays up rather than "Opening albums…" for another
            // timeout.
            guard didBootstrap, Self.shelfHasAlbums(shelfDirectory()) else { return }
            if case .failed = state, retryShelfDownloadsQuietly() { return }
            bootstrap()
            return
        case .loading:
            return
        case .ready:
            break
        }
        guard !indexing else { return }
        let changed = albums.contains { album in
            let current = (try? album.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let indexed = modDates[album.id] ?? .distantPast
            return abs(current.timeIntervalSince(indexed)) >= 1
        }
        // The shelf is listed every time, not only when it had albums at the
        // last load, so one another device has just kept in iCloud joins.
        let folders = withShelf(removableFolderURLs)
        let foldersChanged = folders.map(\.standardizedFileURL.path) != folderURLs.map(\.standardizedFileURL.path)
        let found = scan(folders)
        let pending = Set(found.pending.map(\.lastPathComponent))
        // A new album on the shelf, or one another device added, joins too.
        // Compared with every file the load found, not just the albums that
        // opened: a PDF PDFKit can't open would otherwise look new each time.
        if changed || foldersChanged || loadedFileNames != found.names || pending != pendingShelfAlbumNames {
            load(from: folders)
        } else if found.newerCopies != newerCopies {
            newerCopies = found.newerCopies
        }
    }

    /// What one pass over the folders found: the PDFs to open, the first
    /// folder winning a filename two share (the shelf is first; see
    /// `withShelf`); the shelf albums still to download; every ready filename;
    /// and the chosen folders' copies that are newer than the shelf's.
    struct FolderScan {
        var ready: [URL] = []
        var pending: [URL] = []
        var names: Set<String> = []
        var newerCopies: [String: URL] = [:]
    }

    func scan(_ folders: [URL]) -> FolderScan {
        let shelfPath = shelfDirectory()?.standardizedFileURL.path
        var found = FolderScan()
        var shelfCopies: [String: URL] = [:]
        for folder in folders {
            let listing = AlbumICloudShelf.listing(of: folder)
            let isShelf = folder.standardizedFileURL.path == shelfPath
            for url in listing.ready {
                let name = url.lastPathComponent
                if found.names.insert(name).inserted {
                    found.ready.append(url)
                    if isShelf { shelfCopies[name] = url }
                } else if let kept = shelfCopies[name], Self.isNewer(url, than: found.newerCopies[name] ?? kept) {
                    found.newerCopies[name] = url
                }
            }
            found.pending += listing.pending
        }
        found.pending.removeAll { found.names.contains($0.lastPathComponent) }
        return found
    }

    /// True when `url` was modified at least a second after `other`, the
    /// tolerance the index uses for a changed album. Both come straight from
    /// a folder listing, so their dates are as they are on disk now.
    private static func isNewer(_ url: URL, than other: URL) -> Bool {
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
        }
        return modified(url).timeIntervalSince(modified(other)) >= 1
    }
}
