// UbiquitousDownloadSweep.swift
// Keeps the app's own iCloud files on the iPhone and iPad, so they open offline.

#if !os(macOS)
import Foundation
import OSLog
import UIKit

/// Asks iCloud to download every file in the app's container that is not on
/// this device yet: lesson files, stories, resources, book club packets,
/// student documents and note photos.
///
/// iOS and iPadOS download an iCloud item only when something asks for it
/// (Apple, `startDownloadingUbiquitousItem(at:)`), so a PDF added on the Mac
/// otherwise reaches the iPad only when it is first opened, which in a
/// classroom may be with no network. The Mac keeps its container's files
/// downloaded itself, and reads a file it has evicted transparently, so this
/// runs on iPhone and iPad only.
///
/// One `NSMetadataQuery` over the container's data and documents scopes,
/// stopped as soon as its first gathering finishes; each item not current
/// gets `startDownloadingUbiquitousItem(at:)`, which returns at once and
/// leaves the transfer to the system. Backups are skipped: they are large, and
/// only a restore reads one. Runs after the post-launch migrations and on
/// return to the foreground, at most once an hour, never while iCloud Drive is
/// off, and not while `EnergyPolicy` asks for maintenance to wait.
@MainActor
final class UbiquitousDownloadSweep {
    static let shared = UbiquitousDownloadSweep()

    nonisolated private static let logger = Logger.sync
    /// The shortest gap between two sweeps.
    static let minimumInterval: Duration = .seconds(60 * 60)

    private var query: NSMetadataQuery?
    private var lastRun: ContinuousClock.Instant?
    private var foregroundObserver: NSObjectProtocol?
    private var gatheringObserver: NSObjectProtocol?

    private init() {}

    /// Sweeps now if due, and again whenever the app returns to the
    /// foreground and one is due. Later calls only sweep if due.
    func start() {
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.runIfDue() }
            }
        }
        runIfDue()
    }

    private func runIfDue() {
        guard query == nil else { return }
        if let lastRun, ContinuousClock.now - lastRun < Self.minimumInterval { return }
        guard FileManager.default.ubiquityIdentityToken != nil else { return }
        guard !EnergyPolicy.shared.shouldDeferMaintenance else {
            Self.logger.notice("iCloud download sweep deferred — device hot or in Low Power Mode")
            return
        }
        lastRun = .now

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.operationQueue = .main
        gatheringObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishGathering() }
        }
        self.query = query
        if !query.start() {
            Self.logger.warning("iCloud download sweep: the metadata query did not start")
            finishGathering()
        }
    }

    /// Stops the query and requests a download for every item not current.
    private func finishGathering() {
        guard let query else { return }
        query.disableUpdates()
        query.stop()
        self.query = nil
        if let gatheringObserver {
            NotificationCenter.default.removeObserver(gatheringObserver)
            self.gatheringObserver = nil
        }

        var urls: [URL] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            guard status != NSMetadataUbiquitousItemDownloadingStatusCurrent,
                  !Self.isBackup(url) else { continue }
            urls.append(url)
        }
        guard !urls.isEmpty else { return }
        Task { await Self.requestDownloads(urls) }
    }

    /// Starts each download off the main thread; each call returns at once.
    @concurrent
    private static func requestDownloads(_ urls: [URL]) async {
        var requested = 0
        for url in urls {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                requested += 1
            } catch {
                logger.warning("iCloud download sweep: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.notice("iCloud download sweep requested \(requested, privacy: .public) file(s)")
    }

    /// True for a file in the managed backups folder (`Documents/Backups/`).
    nonisolated static func isBackup(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard let documents = components.lastIndex(of: "Documents"),
              documents + 1 < components.count else { return false }
        return components[documents + 1] == "Backups"
    }
}
#endif
