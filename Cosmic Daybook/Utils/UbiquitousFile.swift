// UbiquitousFile.swift
// Reading, writing and deleting files that live in the app's iCloud container.

import Foundation
import OSLog

/// The file-level rules Apple gives for items in an iCloud ubiquity container,
/// in one place for the managed PDF folders and the note photos.
///
/// - **Files are not always on the device.** iOS and iPadOS download an item
///   in the container only when something asks for it; until then the folder
///   holds a hidden `.<name>.icloud` placeholder and `fileExists` answers
///   false for the real name. macOS keeps the real name but may leave the file
///   dataless ("Optimize Mac Storage"). `isAvailable` counts both as present,
///   and `needsDownload` says whether the bytes still have to arrive.
/// - **Downloading.** `startDownloadingUbiquitousItem(at:)` starts one without
///   waiting (and must not be called inside a coordinator). A *coordinated
///   read* downloads first and runs its accessor once the file is local, which
///   is how `ensureLocal` waits for one the user is opening.
/// - **Coordination.** Writes, moves and deletes in the container go through
///   `NSFileCoordinator`, so iCloud never uploads a half-written file and
///   another process reading the file sees it whole. Reads of a file already
///   local are left uncoordinated: every file here is written once under a new
///   name and never rewritten in place, so there is no torn read to guard
///   against, and a coordinator per thumbnail would cost more than it saves.
nonisolated enum UbiquitousFile {
    private static let logger = Logger.sync

    /// How long `ensureLocal` waits for a download before giving up. A file the
    /// user tapped is small (a PDF or a photo); a minute covers a slow network
    /// without leaving a button spinning forever when there is none.
    static let downloadTimeout: Duration = .seconds(60)

    /// Where coordinated accessors run: off the main thread, at the priority
    /// of the user-facing read that is waiting on them.
    private static let accessQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "UbiquitousFile.access"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    // MARK: - Presence

    /// The hidden stand-in iOS keeps for an item that has not been downloaded:
    /// `.<name>.icloud` next to where the file will be.
    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud", isDirectory: false)
    }

    /// True when the file is on the device, or is an iCloud item waiting to be
    /// downloaded to it.
    static func isAvailable(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholderURL(for: url).path)
    }

    /// True when the file is an iCloud item whose current bytes are not on the
    /// device yet: an iOS placeholder, or a macOS dataless file.
    static func needsDownload(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return fm.fileExists(atPath: placeholderURL(for: url).path)
        }
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true,
              let status = values.ubiquitousItemDownloadingStatus else { return false }
        return status != .current
    }

    // MARK: - Downloading

    /// Starts downloading `url` when it is an iCloud item not yet on the
    /// device, without waiting. Returns whether a download was requested.
    @discardableResult
    static func requestDownloadIfNeeded(_ url: URL) -> Bool {
        guard needsDownload(url) else { return false }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            logger.warning("""
                iCloud download request failed for \(url.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return false
        }
    }

    /// Makes sure the file's bytes are on the device, downloading them first
    /// when they are not. Returns the URL to read (a coordinated read may hand
    /// back a different one), or nil when the file is missing or the download
    /// failed or timed out. The checks and the wait run off the main actor.
    @concurrent
    static func ensureLocal(_ url: URL) async -> URL? {
        guard needsDownload(url) else {
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        do {
            return try await coordinatedRead(at: url) { readURL in
                FileManager.default.fileExists(atPath: readURL.path) ? readURL : nil
            }
        } catch {
            logger.warning("""
                iCloud download failed for \(url.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return nil
        }
    }

    /// The URL to open or read for `url`: the same file once its bytes are on
    /// the device. When it cannot be made local (missing, offline, not an
    /// iCloud item the checks can see, such as a folder reached through a
    /// security-scoped bookmark), `url` itself, so the caller tries exactly
    /// what it tried before.
    @concurrent
    static func localURL(for url: URL) async -> URL {
        await ensureLocal(url) ?? url
    }

    /// Runs `body` inside a coordinated read of `url`, which downloads an
    /// iCloud item first when it is not local. Uses the asynchronous
    /// `coordinate(with:queue:byAccessor:)` Apple recommends, so no thread
    /// blocks while the file arrives; after `downloadTimeout` the coordination
    /// is cancelled.
    static func coordinatedRead<T: Sendable>(
        at url: URL,
        _ body: @escaping @Sendable (URL) throws -> T
    ) async throws -> T {
        let coordinator = CoordinatorBox(NSFileCoordinator(filePresenter: nil))
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
        let timeout = Task {
            try await Task.sleep(for: downloadTimeout)
            coordinator.value.cancel()
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.value.coordinate(with: [intent], queue: accessQueue) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(with: Result { try body(intent.url) })
            }
        }
    }

    // MARK: - Writing, moving, deleting

    /// Writes `data` to `url` under a coordinated write, atomically.
    static func coordinatedWrite(_ data: Data, to url: URL) throws {
        try coordinate(writingAt: url, options: .forReplacing) { target in
            try data.write(to: target, options: .atomic)
        }
    }

    /// Copies `source` to `destination` under a coordinated read of the source
    /// and a coordinated write of the destination.
    static func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source, options: .withoutChanges,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { readURL, writeURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    /// Moves or renames `source` to `destination` under a coordinated move,
    /// telling the coordinator where the item went. Works for an iCloud item
    /// that is not downloaded yet: the move is of the item, not its bytes.
    static func coordinatedMove(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { fromURL, toURL in
            do {
                coordinator.item(at: fromURL, willMoveTo: toURL)
                try FileManager.default.moveItem(at: fromURL, to: toURL)
                coordinator.item(at: fromURL, didMoveTo: toURL)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    /// Deletes `url` under a coordinated delete. A file that is only an iOS
    /// placeholder is deleted through its real name, which removes the item
    /// from iCloud; when the system declines that, the placeholder itself is
    /// removed. Does nothing when neither exists.
    static func coordinatedDelete(_ url: URL) throws {
        guard isAvailable(url) else { return }
        try coordinate(writingAt: url, options: .forDeleting) { target in
            let fm = FileManager.default
            do {
                try fm.removeItem(at: target)
            } catch CocoaError.fileNoSuchFile {
                let placeholder = placeholderURL(for: target)
                if fm.fileExists(atPath: placeholder.path) {
                    try fm.removeItem(at: placeholder)
                }
            }
        }
    }

    /// Runs `body` inside a coordinated write that replaces `url`, for writers
    /// that produce the file their own way (a rename from a temp file).
    static func coordinatedReplace(at url: URL, _ body: (URL) throws -> Void) throws {
        try coordinate(writingAt: url, options: .forReplacing, body)
    }

    /// One coordinated write of `url`; `body` receives the URL to write to and
    /// its error is rethrown.
    private static func coordinate(
        writingAt url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: options, error: &coordinationError
        ) { target in
            do {
                try body(target)
            } catch {
                bodyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let bodyError { throw bodyError }
    }

    /// `NSFileCoordinator` is thread-safe (Apple documents `cancel()` as
    /// callable from any thread) but not marked `Sendable`.
    private final class CoordinatorBox: @unchecked Sendable {
        let value: NSFileCoordinator
        init(_ value: NSFileCoordinator) { self.value = value }
    }
}
