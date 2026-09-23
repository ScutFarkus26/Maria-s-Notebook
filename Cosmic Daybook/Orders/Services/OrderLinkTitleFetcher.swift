// OrderLinkTitleFetcher.swift
// Reads a dropped link's page title, so an item arrives named "Crayola Colored
// Pencils, 24 ct" rather than "amazon.com".

import CoreData
import Foundation
import LinkPresentation

enum OrderLinkTitleFetcher {

    /// The page's title, or nil when the page gives none or doesn't answer in time.
    ///
    /// `LPMetadataProvider` loads the page in WebKit and must be started on the
    /// main thread, which is where this runs. Its completion handler arrives on a
    /// background queue, so it is `@Sendable` and hands back only the title string.
    static func fetchTitle(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        provider.shouldFetchSubresources = false
        let title: String? = await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { @Sendable metadata, _ in
                let raw = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: raw.isEmpty ? nil : raw)
            }
        }
        // The provider must outlive the fetch it started.
        withExtendedLifetime(provider) {}
        return title
    }

    /// Fills in the title of each item that still has none. Saves after each one
    /// lands, so a slow page never holds back the others.
    static func fillMissingTitles(
        _ items: [CDOrderItem],
        save: @escaping () -> Void
    ) async {
        for item in items where item.title.trimmed().isEmpty {
            guard let url = item.url, let title = await fetchTitle(for: url) else { continue }
            // The guide may have typed a title, or deleted the item, while the page loaded.
            guard !item.isDeleted, item.managedObjectContext != nil, item.title.trimmed().isEmpty else {
                continue
            }
            item.title = title
            item.modifiedAt = Date()
            save()
        }
    }
}
