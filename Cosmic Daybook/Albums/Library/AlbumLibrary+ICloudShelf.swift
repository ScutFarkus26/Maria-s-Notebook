// AlbumLibrary+ICloudShelf.swift
// Keeping albums in iCloud so every device finds them, and fetching the ones
// another device kept there.

import Foundation
import OSLog

extension AlbumLibrary {
    /// How long one album may take to download before the library gives up on
    /// it for this session. Albums run to tens of megabytes.
    nonisolated static let albumDownloadTimeout: Duration = .seconds(10 * 60)

    /// `folders` with the iCloud shelf in front, when iCloud Drive is on and the
    /// shelf holds albums (on this device or still to download). First, so its
    /// copy of an album wins over a chosen folder's copy of the same file.
    func withShelf(_ folders: [URL]) -> [URL] {
        guard let shelf = shelfDirectory(), Self.shelfHasAlbums(shelf) else { return folders }
        let shelfPath = shelf.standardizedFileURL.path
        return [shelf] + folders.filter { $0.standardizedFileURL.path != shelfPath }
    }

    static func shelfHasAlbums(_ shelf: URL?) -> Bool {
        guard let shelf else { return false }
        let listing = AlbumICloudShelf.listing(of: shelf)
        return !listing.ready.isEmpty || !listing.pending.isEmpty
    }

    /// The chosen folders, which the guide can remove; the shelf is not one.
    var removableFolderURLs: [URL] {
        let shelfPath = shelfURL?.standardizedFileURL.path
        return folderURLs.filter { $0.standardizedFileURL.path != shelfPath }
    }

    /// True when this album is read from the iCloud shelf.
    func isKeptInICloud(_ album: Album) -> Bool {
        AlbumICloudShelf.contains(album.url, shelf: shelfURL)
    }

    /// True when iCloud Drive is on, so albums can be kept there.
    var canKeepInICloud: Bool {
        shelfDirectory() != nil
    }

    /// How the copy of this album in this device's chosen folders compares
    /// with the shelf's (`AlbumICloudShelf.chosenCopy`).
    func chosenCopy(of album: Album) -> AlbumICloudShelf.ChosenCopy {
        AlbumICloudShelf.chosenCopy(of: album.url, in: removableFolderURLs)
    }

    /// True when one of this device's chosen album folders has a copy of this
    /// album at least as new as the shelf's, and not the shelf's own file, so
    /// removing the shelf copy leaves it behind.
    func hasCopyInChosenFolders(_ album: Album) -> Bool {
        chosenCopy(of: album).isCurrent
    }

    /// A chosen folder's copy of an album kept in iCloud that is newer than
    /// the one on the shelf: the original, edited since it was kept. The shelf
    /// copy wins the name, so without this the edit would go unseen.
    func newerCopy(for album: Album) -> URL? {
        guard isKeptInICloud(album) else { return nil }
        return newerCopies[album.id]
    }

    /// Puts the newer copy from a chosen folder on the shelf in place of the
    /// kept one, so every device reads it, and the kept one goes to the Trash.
    /// The filename stays, so the album's bookmarks, notes and lesson links
    /// stay attached. Nothing changes when the newer copy doesn't open as a
    /// PDF or the old one can't go to the Trash.
    func useNewerCopy(_ album: Album) async {
        guard let newer = newerCopy(for: album), !albumsBeingKept.contains(album.id) else { return }
        albumsBeingKept.insert(album.id)
        #if os(iOS)
        let background = BackgroundTaskAssertion()
        background.begin(named: "Use newer album copy")
        defer { background.end() }
        #endif
        let folder = newer.deletingLastPathComponent().lastPathComponent
        do {
            try await AlbumICloudShelf.replace(album.url, with: newer, trash: trashItem)
        } catch AlbumICloudShelf.Failure.notAPDF {
            shelfError = "The copy of \(album.title) in \(folder) doesn't open as a PDF, "
                + "so the album in iCloud wasn't changed."
        } catch AlbumICloudShelf.Failure.oldCopyNotTrashed {
            shelfError = "Couldn't move the old copy of \(album.title) to \(AlbumICloudShelf.trashName), "
                + "so the album in iCloud wasn't changed."
        } catch AlbumICloudShelf.Failure.notDownloaded {
            shelfError = "Couldn't download \(album.title) to this device, so the album in iCloud wasn't changed. "
                + "Check the network connection and try again."
        } catch {
            Logger.albums.error("Couldn't replace an album in iCloud: \(error.localizedDescription, privacy: .public)")
            shelfError = "Couldn't copy the newer \(album.title) to iCloud. "
                + "Check that iCloud Drive is on and try again."
        }
        albumsBeingKept.remove(album.id)
        reloadFolders()
    }

    // MARK: Keeping and removing

    /// Copies each album not already on the shelf onto it, then reloads so the
    /// shelf's copies are the ones read. The originals stay where they are.
    func keepInICloud(_ albums: [Album]) async {
        guard let shelf = shelfDirectory() else {
            shelfError = "iCloud Drive is off on this device, so albums can't be kept in iCloud."
            return
        }
        let toKeep = albums.filter { !isKeptInICloud($0) && !albumsBeingKept.contains($0.id) }
        guard !toKeep.isEmpty else { return }
        albumsBeingKept.formUnion(toKeep.map(\.id))
        // Leaving the app partway lets the copy finish rather than stop it.
        #if os(iOS)
        let background = BackgroundTaskAssertion()
        background.begin(named: "Keep albums in iCloud")
        defer { background.end() }
        #endif
        var failures: [String] = []
        for album in toKeep {
            do {
                _ = try await AlbumICloudShelf.keep(album.url, on: shelf)
            } catch {
                failures.append(album.title)
            }
            albumsBeingKept.remove(album.id)
        }
        if !failures.isEmpty {
            shelfError = "Couldn't copy \(failures.joined(separator: ", ")) to iCloud."
        }
        reloadFolders()
    }

    /// Takes an album off the shelf, and so out of iCloud on every device.
    /// With a copy at least as new in one of this device's chosen folders,
    /// and `mayDelete` (what the guide confirmed), the shelf copy is deleted
    /// and that copy takes its place. Otherwise it goes to the Trash, since
    /// it may be the only copy of this edition anywhere; if it can't go to
    /// the Trash, nothing is removed. Nothing happens while the album is
    /// being copied.
    func removeFromICloud(_ album: Album, mayDelete: Bool = true) async {
        guard isKeptInICloud(album), !albumsBeingKept.contains(album.id) else { return }
        if mayDelete, hasCopyInChosenFolders(album) {
            do {
                try await AlbumICloudShelf.remove(album.url)
            } catch {
                Logger.albums.error(
                    "Couldn't remove an album from iCloud: \(error.localizedDescription, privacy: .public)"
                )
                shelfError = "Couldn't remove \(album.title) from iCloud. Check that iCloud Drive is on and try again."
            }
        } else {
            do {
                try await AlbumICloudShelf.moveToTrash(album.url, using: trashItem)
            } catch {
                Logger.albums.error(
                    "Couldn't move an album from iCloud to the Trash: \(error.localizedDescription, privacy: .public)"
                )
                shelfError = "Couldn't move \(album.title) to \(AlbumICloudShelf.trashName), so it's still in iCloud."
            }
        }
        reloadFolders()
    }

    /// Loads the chosen folders again with the shelf as it is now.
    func reloadFolders() {
        let folders = withShelf(removableFolderURLs)
        guard !folders.isEmpty else {
            albums = []
            state = .needsFolder
            return
        }
        load(from: folders)
    }

    /// Clears partial copies left on the shelf by a copy that never finished
    /// (`AlbumICloudShelf.removeStalePartials`), once a session, off the main
    /// thread.
    func sweepShelfOnce(_ shelf: URL) {
        guard shelfSweepTask == nil else { return }
        let age = stalePartialAge
        shelfSweepTask = Task.detached(priority: .utility) {
            _ = AlbumICloudShelf.removeStalePartials(in: shelf, olderThan: age)
        }
    }

    // MARK: Downloading

    /// Fetches albums another device kept in iCloud that are not on this one
    /// yet, all at once, and reloads once any arrives: offline, the run ends
    /// after one download timeout rather than one per album. One download run
    /// at a time; a load while it runs leaves its own pending albums to the
    /// reload.
    func downloadPendingAlbums(_ urls: [URL]) {
        guard !urls.isEmpty, shelfDownloadTask == nil else { return }
        let download = downloadAlbum
        shelfDownloadTask = Task {
            let arrived = await withTaskGroup(of: Bool.self) { group in
                for url in urls {
                    group.addTask {
                        // Counted only once its bytes are really here, so a file iCloud
                        // still reports as downloading can't make the reload loop.
                        let local = await download(url)
                        return local != nil && !UbiquitousFile.needsDownload(url)
                    }
                }
                var count = 0
                for await came in group where came {
                    count += 1
                }
                return count
            }
            shelfDownloadTask = nil
            if arrived > 0 {
                load(from: folderURLs)
            } else if state == .loading {
                // Nothing to open came down (a load that found only albums
                // still in iCloud leaves the list empty), so say so rather
                // than leave "Opening albums…" up for the session.
                state = .failed("Your albums in iCloud couldn't be downloaded yet. "
                    + "Check the network connection; they download the next time the app opens.")
            }
        }
    }

    /// After a download run that brought nothing, coming back to the app
    /// tries the same albums again in the background instead of reloading,
    /// which would put "Opening albums…" back up for another timeout. True
    /// when that is what happened: nothing in the folders opens yet and the
    /// same albums are still waiting.
    func retryShelfDownloadsQuietly() -> Bool {
        guard !pendingShelfAlbumNames.isEmpty else { return false }
        let found = scan(withShelf(removableFolderURLs))
        guard found.ready.isEmpty, Set(found.pending.map(\.lastPathComponent)) == pendingShelfAlbumNames else {
            return false
        }
        downloadPendingAlbums(found.pending)
        return true
    }
}
