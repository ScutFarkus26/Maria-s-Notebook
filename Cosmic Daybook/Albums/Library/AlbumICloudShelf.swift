// AlbumICloudShelf.swift
// The albums kept in iCloud: a folder every device finds without being pointed at it.

import Foundation
import OSLog

/// `Documents/Albums/` in the app's iCloud container — iCloud Drive › Cosmic
/// Daybook › Albums in Files and Finder.
///
/// Album folders the guide chooses are reached through security-scoped
/// bookmarks, and a bookmark made on one device cannot open anything on
/// another, so each device used to need its folders chosen again. A PDF kept
/// here is in the app's own container instead: every device signed in to the
/// same iCloud account lists it with no bookmark at all. "Keep in iCloud"
/// copies an album here under its own filename, the album's identity, so its
/// bookmarks, notes, highlights and ink stay attached. The guide can also drop
/// PDFs into the folder from Files or Finder.
///
/// On iPhone and iPad an album added on another device is a placeholder until
/// downloaded (see `UbiquitousFile`); `listing(of:)` reports those as pending
/// so the library can download them before opening them.
nonisolated enum AlbumICloudShelf {
    private static let logger = Logger.albums
    static let folderName = "Albums"

    /// A folder's album PDFs: the ones on this device, and the ones still to
    /// download (by their real names).
    struct Listing: Equatable {
        var ready: [URL] = []
        var pending: [URL] = []
    }

    /// The shelf folder, created if needed; nil when iCloud Drive is
    /// unavailable. The container comes from `UbiquityContainerCache`.
    static func directory(container: UbiquityContainerCache = .shared) -> URL? {
        guard let containerURL = container.url() else { return nil }
        let directory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            logger.warning("Couldn't create the iCloud albums folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// True when `url` is a file on the shelf.
    static func contains(_ url: URL, shelf: URL?) -> Bool {
        guard let shelf else { return false }
        return url.standardizedFileURL.deletingLastPathComponent().path == shelf.standardizedFileURL.path
    }

    /// The PDFs directly inside `folder`. A PDF whose bytes are not on this
    /// device (an iOS `.<name>.pdf.icloud` placeholder or a macOS dataless
    /// file) is pending rather than ready, so nothing opens it on the main
    /// thread and waits for the network.
    static func listing(of folder: URL) -> Listing {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var listing = Listing()
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix("."), name.lowercased().hasSuffix(".pdf.icloud") {
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                listing.pending.append(folder.appendingPathComponent(realName, isDirectory: false))
            } else if entry.pathExtension.lowercased() == "pdf", !name.hasPrefix(".") {
                if UbiquitousFile.needsDownload(entry) {
                    listing.pending.append(entry)
                } else {
                    listing.ready.append(entry)
                }
            }
        }
        return listing
    }

    /// Copies an album onto the shelf under its own filename, off the main
    /// thread (an album can be tens of megabytes). Returns false when the
    /// shelf already holds a file of that name, which is left untouched.
    @concurrent
    static func keep(_ source: URL, on shelf: URL) async throws -> Bool {
        let destination = shelf.appendingPathComponent(source.lastPathComponent, isDirectory: false)
        guard !UbiquitousFile.isAvailable(destination) else { return false }
        try UbiquitousFile.coordinatedCopy(from: source, to: destination)
        return true
    }

    /// Deletes an album from the shelf, which removes it from iCloud on every
    /// device. Copies in chosen folders are not touched.
    @concurrent
    static func remove(_ url: URL) async throws {
        try UbiquitousFile.coordinatedDelete(url)
    }
}
