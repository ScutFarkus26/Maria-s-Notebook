// AlbumLibrary+MemoryPressure.swift
// Releases the album library's recoverable caches when the system asks for memory.

import Foundation

extension AlbumLibrary {

    /// The library is app-lifetime and independent of the active classroom, so nothing
    /// else ever drops what it holds: the full page text of every album PDF (and a
    /// folded copy once a search has needed one), a rendered cover per album, every
    /// PDF opened for reading, and the semantic index's embedding vectors. That made
    /// it the largest resident allocation in the app and the only large one
    /// `AppDependencies.handleMemoryPressure` did not reach.
    ///
    /// Every piece released here is backed by an on-disk cache in Application Support
    /// or by the PDF itself, so recovering costs a reload, not a re-extraction.
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
    /// text and covers rebuild on demand, and album PDFs reopen when next read. At
    /// `.critical` the page-text and semantic indexes go too, which surfaces as the
    /// normal "still indexing" state until `ensureIndexed()` reloads them from disk.
    func releaseMemory(critical: Bool) {
        folds.dropAll()
        // The cached query models (the contextual one is large) reload on the
        // next search.
        AlbumSemanticIndex.releaseQueryEmbedders()
        for album in albums {
            album.releaseCover()
            // Each PDF closes with the page objects and page text reading built
            // up in it, unless a reader still shows it: that one stays as it is.
            album.releaseDocument()
        }
        guard critical else { return }
        pageTexts.removeAll()
        indexPurged = true
        semantic.purge()
    }
}
