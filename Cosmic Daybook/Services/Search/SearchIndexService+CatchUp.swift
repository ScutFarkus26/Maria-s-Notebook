//
//  SearchIndexService+CatchUp.swift
//  Cosmic Daybook
//
//  Keeps the search index current during a session.
//
//  The launch refresh brings the index up to the history token current at
//  launch; nothing moved it after that, so a student deleted mid-session kept
//  turning up in `search_notebook` until the next launch (2026-09-28). The
//  catch-up reuses the launch path's history replay instead of watching every
//  save: after a burst of `.NSPersistentStoreRemoteChange` (posted for this
//  process's saves as well as CloudKit imports) it waits `catchUpDelay`, then
//  replays the history since the token the index is current to and patches
//  the in-memory contents off the main actor. Searches that can follow a write
//  closely (MCP, the in-app assistant) call `ensureReady()`, which runs the
//  same catch-up at once rather than waiting out the delay.
//
//  Cost when nothing searchable changed: comparing two archived tokens (no
//  history fetch) when nothing was written at all, or one history fetch when
//  only other entities were. The snapshot on disk is left alone; the next
//  launch replays from its own token as before.
//

import CoreData
import Foundation
import OSLog

/// Result of replaying in-session history over the live index.
nonisolated enum SearchIndexCatchUp: Sendable {
    /// Nothing searchable changed; the index is current to the new token.
    case unchanged
    case patched(SearchIndexContents)
    /// History since the token is unreadable, or too long to patch; refresh.
    case fallback(reason: String)
}

extension SearchIndexService {

    // MARK: - Following the store

    /// Listens for store changes on `container`'s coordinator. Replaces the
    /// previous subscription when the index moves to another container
    /// (Sample Class, a reset store).
    func follow(_ container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        guard followedCoordinator !== coordinator else { return }
        followTask?.cancel()
        scheduledCatchUp?.cancel()
        scheduledCatchUp = nil
        followedCoordinator = coordinator
        followTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange, object: coordinator)
                .map { _ in () }
            for await _ in changes {
                self?.scheduleCatchUp()
            }
        }
    }

    /// Runs one catch-up `catchUpDelay` after the first change of a burst;
    /// changes arriving meanwhile ride along (a fixed window, like
    /// `CoreDataStack.scheduleCoalescedRemoteChangePass`, so a long import
    /// still gets a pass that often). Self-initiated, so it waits out a hot
    /// device or Low Power Mode; a search in the meantime catches up itself.
    private func scheduleCatchUp() {
        guard isReady, scheduledCatchUp == nil else { return }
        scheduledCatchUp = Task { [weak self] in
            guard let delay = self?.catchUpDelay else { return }
            try? await Task.sleep(for: delay)
            await EnergyPolicy.shared.waitUntilMaintenanceAllowed()
            guard let self, !Task.isCancelled else { return }
            scheduledCatchUp = nil
            await catchUp()
        }
    }

    // MARK: - Catch-up

    /// Replays history written since the index was last brought current.
    /// A no-op when the store's token has not moved. Concurrent callers share
    /// the pass in flight, then re-check the token, so a save that landed
    /// during it is not missed.
    ///
    /// An index built while the store had no history at all (an empty notebook
    /// at launch) has no token to replay from: once there is history, it is
    /// rebuilt. It used to stay as built for the rest of the session.
    func catchUp() async {
        while let running = catchUpTask {
            await running.value
        }
        guard isReady, let container = indexingContainer else { return }
        let current = Self.archivedCurrentHistoryToken(of: container)
        guard let since = indexedHistoryToken else {
            if current != nil { await refresh(container: container) }
            return
        }
        guard let current, current != since else { return }

        let task = Task { [weak self] in
            await self?.runCatchUp(container: container, since: since, current: current)
            self?.catchUpTask = nil
        }
        catchUpTask = task
        await task.value
    }

    private func runCatchUp(container: NSPersistentContainer, since: Data, current: Data) async {
        catchUpPasses += 1
        let generation = contentsGeneration
        let outcome = await Self.catchUpContents(
            contents,
            since: since,
            context: container.newBackgroundContext(),
            changeLimit: incrementalChangeLimit
        )
        // A refresh or purge replaced the contents while this ran.
        guard generation == contentsGeneration, isReady else { return }

        switch outcome {
        case .unchanged:
            indexedHistoryToken = current
        case .patched(let patched):
            setContents(patched)
            indexedHistoryToken = current
            Self.logger.debug("Search index caught up: \(patched.resultsById.count) entities")
        case .fallback(let reason):
            Self.logger.info("Search index catch-up: \(reason, privacy: .public); refreshing")
            await refresh(container: container)
        }
    }

    /// Replays history after `since` over `contents`, off the main actor.
    ///
    /// An object inserted or updated is re-read and re-indexed under its
    /// current text; one deleted is dropped. When a dropped id is shared by
    /// another indexed object (a duplicate not yet folded), that object is
    /// re-read too, so deleting one copy does not hide the other.
    @concurrent
    nonisolated static func catchUpContents(
        _ contents: SearchIndexContents,
        since: Data,
        context: NSManagedObjectContext,
        changeLimit: Int
    ) async -> SearchIndexCatchUp {
        guard let token = unarchiveToken(since) else {
            return .fallback(reason: "indexed history token is unreadable")
        }
        let idsByURI = contents.idsByURI
        let replay = await context.perform {
            readPatch(after: token, idsByURI: idsByURI, context: context, changeLimit: changeLimit)
        }

        switch replay {
        case .failure(let failure):
            return .fallback(reason: failure.reason)
        case .success(nil):
            return .unchanged
        case .success(let patch?):
            var patched = contents
            patched.remove(ids: patch.removedIDs, objectURIs: patch.forgottenURIs)
            for entry in patch.entries {
                patched.add(entry.result, text: entry.text, objectURI: entry.objectURI)
            }
            return .patched(patched)
        }
    }

    nonisolated struct CatchUpFailure: Error {
        let reason: String
    }

    /// What one catch-up changes: ids to drop, URIs to forget, entries to (re)add.
    nonisolated struct CatchUpPatch: Sendable {
        var removedIDs: Set<UUID>
        var forgottenURIs: [String]
        var entries: [SearchIndexSnapshot.Entry]
    }

    /// Reads the history after `token` into a patch; `nil` when nothing
    /// searchable changed. Inside `context.perform`.
    private nonisolated static func readPatch(
        after token: NSPersistentHistoryToken,
        idsByURI: [String: UUID],
        context: NSManagedObjectContext,
        changeLimit: Int
    ) -> Result<CatchUpPatch?, CatchUpFailure> {
        let changes: SearchableHistoryChanges
        do {
            changes = try fetchSearchableChanges(after: token, context: context)
        } catch {
            let reason = "history since the index is unavailable (\(error.localizedDescription))"
            return .failure(CatchUpFailure(reason: reason))
        }
        guard !changes.isEmpty else { return .success(nil) }
        guard changes.count <= changeLimit else {
            return .failure(CatchUpFailure(reason: "\(changes.count) searchable changes exceed the incremental limit"))
        }

        let changedURIs = changes.deleted.union(changes.touched.keys)
        let removedIDs = Set(changedURIs.compactMap { idsByURI[$0] })
        var entries = changes.touched.values.compactMap { objectID in
            context.existing(objectID).flatMap(entry(for:))
        }
        // Other objects carrying a dropped id come back under their own text.
        if !removedIDs.isEmpty, let coordinator = context.persistentStoreCoordinator {
            for (uri, id) in idsByURI where removedIDs.contains(id) && !changedURIs.contains(uri) {
                guard let url = URL(string: uri),
                      let objectID = coordinator.managedObjectID(forURIRepresentation: url),
                      let entry = context.existing(objectID).flatMap(entry(for:)) else { continue }
                entries.append(entry)
            }
        }
        return .success(CatchUpPatch(removedIDs: removedIDs, forgottenURIs: Array(changedURIs), entries: entries))
    }
}
