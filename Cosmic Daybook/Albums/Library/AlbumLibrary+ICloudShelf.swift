// AlbumLibrary+ICloudShelf.swift
// Keeping albums in iCloud so every device finds them, and fetching the ones
// another device kept there.

import Foundation
import OSLog

extension AlbumLibrary {
    /// How long one album may take to download before the library gives up on
    /// it for this session. Albums run to tens of megabytes.
    static let albumDownloadTimeout: Duration = .seconds(10 * 60)

    /// `folders` with the iCloud shelf in front, when iCloud Drive is on and the
    /// shelf holds albums (on this device or still to download). First, so its
    /// copy of an album wins over a chosen folder's copy of the same file.
    func withShelf(_ folders: [URL]) -> [URL] {
        guard let shelf = AlbumICloudShelf.directory(), Self.shelfHasAlbums(shelf) else { return folders }
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
        AlbumICloudShelf.directory() != nil
    }

    // MARK: Keeping and removing

    /// Copies each album not already on the shelf onto it, then reloads so the
    /// shelf's copies are the ones read. The originals stay where they are.
    func keepInICloud(_ albums: [Album]) async {
        guard let shelf = AlbumICloudShelf.directory() else {
            shelfError = "iCloud Drive is off on this device, so albums can't be kept in iCloud."
            return
        }
        let toKeep = albums.filter { !isKeptInICloud($0) }
        guard !toKeep.isEmpty else { return }
        albumsBeingKept.formUnion(toKeep.map(\.id))
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

    /// Deletes an album from the shelf, and so from iCloud on every device. A
    /// copy in a chosen folder takes its place; with none, the album leaves the
    /// library.
    func removeFromICloud(_ album: Album) async {
        guard isKeptInICloud(album) else { return }
        do {
            try await AlbumICloudShelf.remove(album.url)
        } catch {
            Logger.albums.error("Couldn't remove an album from iCloud: \(error.localizedDescription, privacy: .public)")
            shelfError = "Couldn't remove \(album.title) from iCloud. Check that iCloud Drive is on and try again."
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

    // MARK: Downloading

    /// Fetches albums another device kept in iCloud that are not on this one
    /// yet, one at a time, and reloads once any arrives. One download run at a
    /// time; a load while it runs leaves its own pending albums to the reload.
    func downloadPendingAlbums(_ urls: [URL]) {
        guard !urls.isEmpty, shelfDownloadTask == nil else { return }
        shelfDownloadTask = Task {
            var arrived = 0
            for url in urls {
                let local = await UbiquitousFile.ensureLocal(url, timeout: Self.albumDownloadTimeout)
                // Counted only once its bytes are really here, so a file iCloud
                // still reports as downloading can't make the reload loop.
                if local != nil, !UbiquitousFile.needsDownload(url) {
                    arrived += 1
                }
            }
            shelfDownloadTask = nil
            if arrived > 0 {
                load(from: folderURLs)
            } else if albums.isEmpty, state == .loading {
                state = .failed("Your albums in iCloud couldn't be downloaded yet. "
                    + "Check the network connection; they download the next time the app opens.")
            }
        }
    }
}
