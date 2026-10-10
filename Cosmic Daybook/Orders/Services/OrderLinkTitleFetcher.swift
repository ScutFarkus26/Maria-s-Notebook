// OrderLinkTitleFetcher.swift
// Reads a dropped link's page title, so an item arrives named "Crayola Colored
// Pencils, 24 ct" rather than "amazon.com".

import CoreData
import Foundation
import LinkPresentation

enum OrderLinkTitleFetcher {

    /// What reading a page found.
    nonisolated enum PageAnswer: Equatable, Sendable {
        case title(String)
        /// The page answered with no title: reading it again won't give one.
        case noTitle
        /// The page didn't answer (offline, the connection dropped, too slow): worth
        /// reading again the next time Restock appears.
        case noAnswer

        var title: String? {
            if case .title(let title) = self { title } else { nil }
        }
    }

    /// The page's title, or nil when the page gives none or doesn't answer in time.
    static func fetchTitle(for url: URL) async -> String? {
        await readPage(url).title
    }

    /// Reads a page for its title, telling a page with no title apart from one
    /// that didn't answer.
    ///
    /// `LPMetadataProvider` loads the page in WebKit and must be started on the
    /// main thread, which is where this runs. Its completion handler arrives on a
    /// background queue, so it is `@Sendable` and hands back only the answer.
    static func readPage(_ url: URL) async -> PageAnswer {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        provider.shouldFetchSubresources = false
        let answer: PageAnswer = await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { @Sendable metadata, error in
                if let error {
                    continuation.resume(returning: answer(for: error))
                    return
                }
                guard let metadata else {
                    continuation.resume(returning: .noTitle)
                    return
                }
                let raw = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: raw.isEmpty ? .noTitle : .title(raw))
            }
        }
        // The provider must outlive the fetch it started.
        withExtendedLifetime(provider) {}
        return answer
    }

    /// What a failed read means. Only the network being away (offline, the
    /// connection dropped, too slow) is "didn't answer", worth reading again
    /// later; anything else (a dead link, a site that refuses previews) is
    /// an answer with no title, so it isn't loaded again on every visit.
    nonisolated static func answer(for error: any Error) -> PageAnswer {
        isNetworkAway(error as NSError) ? .noAnswer : .noTitle
    }

    private nonisolated static func isNetworkAway(_ error: NSError) -> Bool {
        if error.domain == LPErrorDomain, error.code == LPError.Code.metadataFetchTimedOut.rawValue {
            return true
        }
        let networkAway: Set<Int> = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive
        ]
        if error.domain == NSURLErrorDomain, networkAway.contains(error.code) { return true }
        // LinkPresentation wraps the network's own error.
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isNetworkAway(underlying)
    }

    /// How many times a launch reads a page that didn't answer before leaving
    /// it until the app is opened again.
    static let unansweredReadLimit = 3

    /// Reads a page: `readPage`, or a test's stand-in.
    typealias TitleFetch = (URL) async -> PageAnswer

    /// The needs this launch has had an answer for, so a page that gives no
    /// title isn't read again every time Restock appears. A page that didn't
    /// answer is read again next time, up to `unansweredReadLimit` reads a
    /// launch (bug hunt 2026-10-10 #22: offline when Restock first appeared
    /// meant "amazon.com" until the app was opened again).
    private static var tried: Set<NSManagedObjectID> = []
    /// How many times this launch each need's page didn't answer; at
    /// `unansweredReadLimit` it joins `tried`.
    private static var unanswered: [NSManagedObjectID: Int] = [:]
    /// The needs whose page is being read now, by Restock or the request
    /// draft: the other screen leaves them be, and the draft picks up the
    /// title when its save lands.
    private static var reading: Set<NSManagedObjectID> = []

    /// The open needs with a web link and no title, saved, not being read and
    /// not yet answered this launch: links an assistant pasted (her phone
    /// reads no pages), or added while their page didn't answer.
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
    /// once its page has answered, with a title or without, so each is read
    /// once a launch; one whose page didn't answer is read again next time.
    /// Leaving the screen stops the rest.
    static func fillUntitled(
        _ needs: [CDOrderItem],
        fetch: TitleFetch = readPage(_:),
        save: @escaping () -> Void
    ) async {
        for need in untitledNeeds(needs) {
            guard !Task.isCancelled else { return }
            // The other screen may have started this one meanwhile.
            guard wantsTitle(need) else { continue }
            let id = need.objectID
            reading.insert(id)
            let answer = await fillMissingTitle(need, fetch: fetch, save: save)
            reading.remove(id)
            if answer == .noAnswer {
                let count = unanswered[id, default: 0] + 1
                unanswered[id] = count
                if count >= unansweredReadLimit { tried.insert(id) }
            } else {
                tried.insert(id)
            }
        }
    }

    /// Fills in the title of each item that still has none, shortened
    /// (`RestockService.applyFetchedTitle`). Saves after each one lands, so a slow
    /// page never holds back the others.
    static func fillMissingTitles(
        _ items: [CDOrderItem],
        fetch: TitleFetch = readPage(_:),
        save: @escaping () -> Void
    ) async {
        for item in items {
            await fillMissingTitle(item, fetch: fetch, save: save)
        }
    }

    /// Reads one item's page while it has no title, and fills the title in.
    /// Returns what the page said; nil when there was nothing to read.
    @discardableResult
    private static func fillMissingTitle(
        _ item: CDOrderItem,
        fetch: TitleFetch,
        save: () -> Void
    ) async -> PageAnswer? {
        guard item.title.trimmed().isEmpty, let url = item.url else { return nil }
        let answer = await fetch(url)
        // The guide may have typed a title, or deleted the item, while the page loaded.
        guard let title = answer.title, RestockService.applyFetchedTitle(title, to: item) else { return answer }
        save()
        return answer
    }
}
