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

    /// Reads a page's title: `fetchTitle`, or a test's stand-in.
    typealias TitleFetch = (URL) async -> String?

    /// The needs this launch has finished reading a page for, so a page that
    /// gives no title isn't read again every time Restock appears.
    private static var tried: Set<NSManagedObjectID> = []
    /// The needs whose page is being read now, by Restock or the request
    /// draft: the other screen leaves them be, and the draft picks up the
    /// title when its save lands.
    private static var reading: Set<NSManagedObjectID> = []

    /// The open needs with a web link and no title, saved, not being read and
    /// not yet tried this launch: links an assistant pasted (her phone reads
    /// no pages), or added while their page didn't answer.
    static func untitledNeeds(_ needs: [CDOrderItem]) -> [CDOrderItem] {
        needs.filter(wantsTitle)
    }

    private static func wantsTitle(_ need: CDOrderItem) -> Bool {
        !need.isDeleted && need.managedObjectContext != nil && need.receivedAt == nil
            && need.title.trimmed().isEmpty && need.url != nil && !need.objectID.isTemporaryID
            && !tried.contains(need.objectID) && !reading.contains(need.objectID)
    }

    /// Fills in the titles `untitledNeeds` finds, one page at a time: when
    /// Restock appears and when the request draft opens, so the email names
    /// each thing rather than printing "amazon.com". A need counts as tried
    /// once its page has answered (or given up), so each is read once a
    /// launch; leaving the screen stops the rest.
    static func fillUntitled(
        _ needs: [CDOrderItem],
        fetch: TitleFetch = fetchTitle(for:),
        save: @escaping () -> Void
    ) async {
        for need in untitledNeeds(needs) {
            guard !Task.isCancelled else { return }
            // The other screen may have started this one meanwhile.
            guard wantsTitle(need) else { continue }
            let id = need.objectID
            reading.insert(id)
            await fillMissingTitles([need], fetch: fetch, save: save)
            reading.remove(id)
            tried.insert(id)
        }
    }

    /// Fills in the title of each item that still has none, shortened
    /// (`RestockService.applyFetchedTitle`). Saves after each one lands, so a slow
    /// page never holds back the others.
    static func fillMissingTitles(
        _ items: [CDOrderItem],
        fetch: TitleFetch = fetchTitle(for:),
        save: @escaping () -> Void
    ) async {
        for item in items where item.title.trimmed().isEmpty {
            guard let url = item.url, let title = await fetch(url) else { continue }
            // The guide may have typed a title, or deleted the item, while the page loaded.
            guard RestockService.applyFetchedTitle(title, to: item) else { continue }
            save()
        }
    }
}
