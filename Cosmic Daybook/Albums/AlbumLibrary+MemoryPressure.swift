// AlbumLibrary+MemoryPressure.swift
// Releases the album library's recoverable caches when the system asks for memory.

import Foundation

extension AlbumLibrary {

    /// The library is app-lifetime and independent of the active classroom, so nothing
    /// else ever drops what it holds: the full page text of every album PDF (twice —
    /// raw and folded), a rendered cover per album, and the semantic index's embedding
    /// vectors. That made it the largest resident allocation in the app and the only
    /// large one `AppDependencies.handleMemoryPressure` did not reach.
    ///
    /// Every piece released here is backed by an on-disk cache in Application Support,
    /// so recovering costs a reload, not a re-extraction from the PDFs.
    func observeMemoryPressure() {
        NotificationCenter.default.addObserver(
            forName: .memoryPressureDetected,
            object: nil,
            queue: .main
        ) { notification in
            let isCritical = (notification.userInfo?["level"] as? MemoryPressureLevel) == .critical
            MainActor.assumeIsolated {
                AlbumLibrary.shared.releaseMemory(critical: isCritical)
            }
        }
    }

    /// Drops recoverable caches. At `.warning` this is invisible to the guide — folded
    /// text and covers rebuild on demand. At `.critical` the page-text and semantic
    /// indexes go too, which surfaces as the normal "still indexing" state until
    /// `ensureIndexed()` reloads them from disk.
    func releaseMemory(critical: Bool) {
        foldedTexts.removeAll()
        for album in albums {
            album.cover = nil
            album.coverRequested = false
        }
        guard critical else { return }
        pageTexts.removeAll()
        indexPurged = true
        semantic.purge()
    }
}
