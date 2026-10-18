// DocumentFileURLMemo.swift
// A stored document's file, resolved once per stored value instead of on every redraw.

import Foundation
import Observation

/// Remembers where a stored document's file was found, so a screen's
/// redraws reuse the answer instead of resolving it again.
///
/// Three screens resolved a stored file inside `body`, so every redraw paid
/// for it: the Student Files card (its thumbnail), the Book Club packet
/// detail (whether Open PDF is enabled; every keystroke in the packet's
/// fields redraws it) and the resource detail (whether Share and Print are
/// offered, and what Share sends). A resolution is a bookmark resolution and
/// a `fileExists` check, and when the bookmark no longer finds the file, the
/// managed folder's lookup and another check for the relative path (see
/// `ManagedPDFFileStorage`).
///
/// A screen keeps one of these in `@State` and reads through it with its
/// library's resolver. The first read resolves exactly as before; later reads
/// with the same bookmark and relative path return that answer until either
/// value changes. A file that wasn't found may be on its way from iCloud: the
/// memo looks again every `recheckInterval` for `recheckLimit` (two minutes),
/// and each recheck redraws the screen (the memo is observable), so Open PDF
/// and a card's thumbnail come back once it lands with nothing else redrawing
/// the screen. Between rechecks, and after the limit, redraws reuse the "not
/// found" answer instead of looking it up each time (review of the 2026-10-17
/// fixes, a2 #10).
///
/// Opening, deleting and printing a document resolve afresh, as they always
/// did, so a file that has since moved, gone or arrived is found (or not)
/// exactly as before.
@Observable
final class DocumentFileURLMemo {

    private struct Key: Equatable {
        let bookmark: Data?
        let relativePath: String
    }

    @ObservationIgnored private var key: Key?
    @ObservationIgnored private var url: URL?
    /// The recheck the last lookup answered; a missing file is looked up
    /// again once `recheck` has moved past it.
    @ObservationIgnored private var lookedUpAtRecheck = 0
    @ObservationIgnored private var rechecking: (key: Key, task: Task<Void, Never>)?
    @ObservationIgnored private let recheckInterval: Duration
    @ObservationIgnored private let recheckLimit: Duration
    /// How many times it has resolved (for tests pinning the memo).
    @ObservationIgnored private(set) var resolutionCount = 0
    /// Moves on at each recheck. The one observed value: a screen that read
    /// through the memo redraws when it changes.
    private var recheck = 0

    init(recheckInterval: Duration = .seconds(3), recheckLimit: Duration = .seconds(120)) {
        self.recheckInterval = recheckInterval
        self.recheckLimit = recheckLimit
    }

    /// The file for `bookmark` and `relativePath`: the remembered answer when
    /// both match the last read and, for a file not found, no recheck is due;
    /// otherwise `resolve`'s.
    func url(
        bookmark: Data?,
        relativePath: String,
        resolve: @MainActor (Data?, String) -> URL?
    ) -> URL? {
        let key = Key(bookmark: bookmark, relativePath: relativePath)
        let recheck = self.recheck
        if key == self.key {
            if let url { return url }
            if recheck == lookedUpAtRecheck { return nil }
        }
        resolutionCount += 1
        url = resolve(bookmark, relativePath)
        self.key = key
        lookedUpAtRecheck = recheck
        if url == nil {
            startRechecking(key)
        } else {
            stopRechecking()
        }
        return url
    }

    /// The same, for a library that keeps only a relative path (Resources).
    func url(relativePath: String, resolve: @MainActor (String) -> URL?) -> URL? {
        url(bookmark: nil, relativePath: relativePath) { _, path in resolve(path) }
    }

    /// Prompts a look every `recheckInterval` until `recheckLimit` has passed,
    /// once per missing value: a recheck that still finds nothing doesn't
    /// restart the clock. The task holds the memo weakly, so a screen that
    /// goes away ends its rechecks at the next one.
    private func startRechecking(_ key: Key) {
        if rechecking?.key == key { return }
        rechecking?.task.cancel()
        let interval = recheckInterval
        let limit = recheckLimit
        let task = Task { [weak self] in
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: limit)
            while clock.now.advanced(by: interval) <= end {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self else { return }
                self.recheck &+= 1
            }
        }
        rechecking = (key, task)
    }

    private func stopRechecking() {
        rechecking?.task.cancel()
        rechecking = nil
    }
}
