// AlbumICloudShelf.swift
// The albums kept in iCloud: a folder every device finds without being pointed at it.

import Foundation
import OSLog
import PDFKit

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
///
/// Everything here deletes, moves or replaces files on every device, so no
/// path removes the only good copy of an album: a copy is checked before it
/// replaces anything, and an album that may be the last of its edition goes
/// to the Trash, never straight out.
nonisolated enum AlbumICloudShelf {
    private static let logger = Logger.albums
    static let folderName = "Albums"

    /// Where an album sent to the Trash turns up, as the guide would look for
    /// it: the Mac's Trash, or Recently Deleted in the Files app on iPhone and
    /// iPad.
    #if os(macOS)
    static let trashName = "the Trash"
    static let moveToTrashTitle = "Move to Trash"
    #else
    static let trashName = "Recently Deleted in the Files app"
    static let moveToTrashTitle = "Move to Recently Deleted"
    #endif

    /// How long Keep in iCloud or Use Newer Copy waits for an album that
    /// isn't on this device to download before giving up.
    static let sourceDownloadTimeout: Duration = .seconds(3 * 60)

    /// How long a copy waits for another app to let go of the file before
    /// giving up; once it has the file, the copy runs to the end.
    static let copyAccessTimeout: Duration = .seconds(60)

    /// A hidden partial copy (`partialURL(for:)`) unchanged for this long was
    /// left by a copy that never finished.
    static let stalePartialAge: TimeInterval = 60 * 60

    /// Why a copy onto the shelf didn't happen; nothing on the shelf changed.
    enum Failure: Error, Equatable {
        /// The album to copy isn't on this device and couldn't be downloaded in time.
        case notDownloaded
        /// The copy doesn't open as a PDF.
        case notAPDF
        /// The old copy couldn't go to the Trash, so it wasn't replaced.
        case oldCopyNotTrashed
    }

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

    // MARK: Another copy here

    /// How this device's chosen folders' copy of a shelf album compares with
    /// the shelf's, for Remove from iCloud. Deleting the shelf copy is safe
    /// only when a chosen folder holds a copy at least as new that is a
    /// different file: a chosen folder can be the shelf itself reached by
    /// another path, so files are compared by identity, not by path.
    enum ChosenCopy: Equatable {
        /// No copy in a chosen folder whose date this device can read (none,
        /// the shelf's own file, or one not downloaded here).
        case missing
        /// A copy older than the shelf's: the shelf holds a revision.
        case older(URL)
        /// A copy at least as new as the shelf's.
        case current(URL)

        /// True for a copy at least as new as the shelf's, the only case in
        /// which the shelf copy may be deleted rather than sent to the Trash.
        var isCurrent: Bool {
            if case .current = self { return true }
            return false
        }
    }

    static func chosenCopy(of kept: URL, in folders: [URL]) -> ChosenCopy {
        guard let keptFile = FileFacts(kept) else { return .missing }
        var older: URL?
        for folder in folders {
            let candidate = folder.appendingPathComponent(kept.lastPathComponent, isDirectory: false)
            guard let file = FileFacts(candidate), !file.identifier.isEqual(keptFile.identifier) else { continue }
            // The reverse of the library's "newer" test (a second's tolerance).
            if keptFile.modified.timeIntervalSince(file.modified) < 1 {
                return .current(candidate)
            }
            older = older ?? candidate
        }
        return older.map { .older($0) } ?? .missing
    }

    /// When `url` was last changed, read fresh; nil when it can't be read.
    static func modificationDate(of url: URL) -> Date? {
        FileFacts(url)?.modified
    }

    /// A file's identity and modification date, read through a fresh URL
    /// (a URL caches resource values, and a replaced album is a new file).
    /// Nil for a file not on the device, such as an iCloud placeholder.
    private struct FileFacts {
        let identifier: NSObject
        let modified: Date

        init?(_ url: URL) {
            let fresh = URL(fileURLWithPath: url.path, isDirectory: false)
            guard let values = try? fresh.resourceValues(
                      forKeys: [.fileResourceIdentifierKey, .contentModificationDateKey]
                  ),
                  let identifier = values.fileResourceIdentifier as? NSObject,
                  let modified = values.contentModificationDate else { return nil }
            self.identifier = identifier
            self.modified = modified
        }
    }

    // MARK: Copying onto the shelf

    /// Copies an album onto the shelf under its own filename, off the main
    /// thread (an album can be tens of megabytes). Returns false when the
    /// shelf already holds a file of that name, which is left untouched. An
    /// album not on this device is downloaded first, within
    /// `sourceDownloadTimeout`. `copy` does the copying; tests stand in one
    /// that fails partway.
    @concurrent
    static func keep(
        _ source: URL, on shelf: URL,
        copy: @Sendable (URL, URL) async throws -> Void = copyWithinLimit
    ) async throws -> Bool {
        let destination = shelf.appendingPathComponent(source.lastPathComponent, isDirectory: false)
        guard !UbiquitousFile.isAvailable(destination) else { return false }
        let local = try await downloaded(source)
        // Copied under a hidden name and moved into place whole: a copy that
        // fails partway never leaves a broken PDF under the album's name,
        // which every device would take for the real album.
        let partial = partialURL(for: destination)
        do {
            try await copy(local, partial)
            try UbiquitousFile.coordinatedMove(from: partial, to: destination)
        } catch {
            try? UbiquitousFile.coordinatedDelete(partial)
            throw error
        }
        return true
    }

    /// Replaces the shelf's copy of an album with `source` (a newer copy in a
    /// chosen folder). Nothing on the shelf changes until the new copy is
    /// whole and opens as a PDF, and a copy of the old one is in the Trash:
    /// 1. `source` is copied beside the album under a hidden name and checked;
    /// 2. the old copy is copied into a hidden folder and sent to the Trash
    ///    from there, under the album's own name, so it can be got back;
    /// 3. the new copy is swapped in whole, so every device reads the old
    ///    album or the new one.
    /// Throws a `Failure` (or the copy's error) having changed nothing.
    @concurrent
    static func replace(
        _ kept: URL, with source: URL,
        copy: @Sendable (URL, URL) async throws -> Void = copyWithinLimit,
        trash: @Sendable (URL) throws -> Void = UbiquitousFile.coordinatedTrash
    ) async throws {
        let incoming = try await downloaded(source)
        let current = try await downloaded(kept)
        let partial = partialURL(for: kept)
        do {
            try await copy(incoming, partial)
            guard opensAsPDF(partial) else { throw Failure.notAPDF }
            try await sendCopyToTrash(of: current, named: kept.lastPathComponent, trash: trash)
            try UbiquitousFile.coordinatedReplaceItem(at: kept, withItemAt: partial)
        } catch {
            try? UbiquitousFile.coordinatedDelete(partial)
            throw error
        }
    }

    /// The copy `keep` and `replace` make unless a test stands in its own:
    /// coordinated, waiting at most `copyAccessTimeout` for the files.
    static func copyWithinLimit(_ source: URL, _ destination: URL) async throws {
        try await UbiquitousFile.coordinatedCopy(from: source, to: destination, timeout: copyAccessTimeout)
    }

    /// True when `url` opens as a PDF with at least one page.
    static func opensAsPDF(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        return document.pageCount > 0
    }

    /// `url` with its bytes on this device, downloaded first when needed.
    private static func downloaded(_ url: URL) async throws -> URL {
        guard let local = await UbiquitousFile.ensureLocal(url, timeout: sourceDownloadTimeout) else {
            throw Failure.notDownloaded
        }
        return local
    }

    /// Sends a copy of `url` to the Trash as `name`, leaving `url` where it
    /// is. The copy is made in a hidden folder beside it (listings never look
    /// inside folders), so the Trash holds a file the guide can find by the
    /// album's name. When the Trash refuses it, the copy is deleted (the
    /// original is untouched) and `.oldCopyNotTrashed` thrown.
    private static func sendCopyToTrash(
        of url: URL, named name: String, trash: @Sendable (URL) throws -> Void
    ) async throws {
        let holder = url.deletingLastPathComponent()
            .appendingPathComponent(".Replaced \(UUID().uuidString)", isDirectory: true)
        try UbiquitousFile.coordinatedReplace(at: holder) { target in
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        }
        defer { removeIfEmpty(holder) }
        let saved = holder.appendingPathComponent(name, isDirectory: false)
        do {
            try await copyWithinLimit(url, saved)
        } catch {
            try? UbiquitousFile.coordinatedDelete(saved)
            throw error
        }
        do {
            try trash(saved)
        } catch {
            logger.error("""
                Couldn't move an album's old copy to the Trash: \(error.localizedDescription, privacy: .public)
                """)
            try? UbiquitousFile.coordinatedDelete(saved)
            throw Failure.oldCopyNotTrashed
        }
    }

    /// Deletes `folder` when nothing is left in it; never a folder holding a file.
    private static func removeIfEmpty(_ folder: URL) {
        guard let left = try? FileManager.default.contentsOfDirectory(atPath: folder.path), left.isEmpty else {
            return
        }
        try? UbiquitousFile.coordinatedDelete(folder)
    }

    /// A hidden name beside `destination` for a copy on its way in. Listings
    /// skip it (hidden, and not a PDF), here and on every other device.
    static func partialURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).partial", isDirectory: false
        )
    }

    /// Deletes the partial copies (`partialURL(for:)`) on the shelf that a
    /// copy which never finished left behind: the app quit or crashed partway,
    /// here or on another device. A copy keeps its source's dates, so a
    /// partial counts as stale only when even its latest date (when it last
    /// changed on this device) is older than `age`. A partial is never the
    /// only copy of anything. Returns the names removed.
    static func removeStalePartials(
        in shelf: URL, olderThan age: TimeInterval = stalePartialAge, now: Date = .now
    ) -> [String] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .attributeModificationDateKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: shelf, includingPropertiesForKeys: keys
        )) ?? []
        var removed: [String] = []
        for entry in entries {
            guard let target = partialTarget(entry, in: shelf),
                  let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            let dates = [values.creationDate, values.contentModificationDate, values.attributeModificationDate]
            guard let latest = dates.compactMap({ $0 }).max(), now.timeIntervalSince(latest) > age else { continue }
            do {
                try UbiquitousFile.coordinatedDelete(target)
                removed.append(entry.lastPathComponent)
            } catch {
                logger.warning("""
                    Couldn't clear a leftover album copy: \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        return removed
    }

    /// The partial copy `entry` stands for (itself, or the real name of its
    /// iOS placeholder), or nil when it isn't one: only a hidden
    /// `.<name>.<UUID>.partial` counts.
    private static func partialTarget(_ entry: URL, in shelf: URL) -> URL? {
        var name = entry.lastPathComponent
        if name.hasPrefix(".."), name.hasSuffix(".partial.icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
        }
        guard name.hasPrefix("."), name.hasSuffix(".partial") else { return nil }
        let stem = name.dropLast(".partial".count)
        guard let dot = stem.lastIndex(of: "."), UUID(uuidString: String(stem[stem.index(after: dot)...])) != nil,
              dot > stem.index(after: stem.startIndex) else { return nil }
        return shelf.appendingPathComponent(name, isDirectory: false)
    }

    // MARK: Taking albums off the shelf

    /// Deletes an album from the shelf, which removes it from iCloud on every
    /// device. Copies in chosen folders are not touched.
    @concurrent
    static func remove(_ url: URL) async throws {
        try UbiquitousFile.coordinatedDelete(url)
    }

    /// Moves an album on the shelf to the Trash, which takes it out of iCloud
    /// on every device but leaves it to be got back. `trash` does the move
    /// (`UbiquitousFile.coordinatedTrash`); when it throws, nothing has moved.
    @concurrent
    static func moveToTrash(_ url: URL, using trash: @Sendable (URL) throws -> Void) async throws {
        try trash(url)
    }
}
