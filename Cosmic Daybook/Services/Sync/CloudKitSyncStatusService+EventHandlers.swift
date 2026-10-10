import Foundation
import SwiftUI
import CoreData
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Event Handlers

extension CloudKitSyncStatusService {

    // MARK: - Network & iCloud Change Handlers

    func handleNetworkChange(isAvailable: Bool) {
        if isAvailable {
            // Network restored - clear a network error (by its kind, not its
            // wording; see `loadPersistedSyncError`) and trigger retry
            if lastSyncErrorKind == .network {
                clearSyncErrorInMemory()
                Self.removePersistedSyncError()
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        }
        updateSyncHealth()
    }

    func handleICloudAccountChange(isAvailable: Bool) {
        if isAvailable {
            // User signed into iCloud - clear an account error and retry
            if lastSyncErrorKind == .account {
                clearSyncErrorInMemory()
                Self.removePersistedSyncError()
            }
            // Trigger retry for any pending syncs
            retryPendingSync()
        }
        updateSyncHealth()
    }

    // MARK: - Event Handlers

    func handleStoreCoordinatorChange() {
        // The persistent store coordinator's stores changed.
        // This fires when stores are added/removed — commonly during:
        // 1. Initial CloudKit setup (SwiftData creates temp stores that get torn down)
        // 2. Scene phase transitions on macOS (expected SwiftUI lifecycle)
        // 3. CloudKit mirroring delegate teardown/rebuild
        //
        // Best practice (Apple TN3164): NSCloudKitMirroringDelegate instances are tied
        // to a specific NSPersistentStore lifecycle. Store changes cause the delegate
        // to tear down and attempt recovery. We should not interfere with this process.

        // During app initialization (first 15 seconds), these changes are expected
        // as SwiftData sets up CloudKit integration. Ignore them to avoid false "offline" reports.
        let timeSinceInit = Date().timeIntervalSince(initializationTime)
        if timeSinceInit < 15 {
            return
        }

        // Cancel any in-flight sync timeout task immediately.
        // The store coordinator change means CloudKit's mirroring delegate is
        // tearing down and rebuilding — any pending sync timeout is now stale
        // and would produce CancellationError log noise if left running.
        syncingTask?.cancel()
        syncingTask = nil
        if isSyncing {
            isSyncing = false
            pendingSyncCount = 0
        }
        cloudImportDebounceTask?.cancel()
        isImportingFromCloud = false

        let isEnabled = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
        let isActive = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)

        guard isEnabled && isActive else { return }

        // Schedule a delayed health check to see if CloudKit reconnects
        // If it doesn't reconnect within 5 seconds, update health status.
        // This gives the mirroring delegate time to complete its teardown/rebuild cycle.
        Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — another store change arrived
            } catch {
                return
            }
            guard let self else { return }
            self.updateSyncHealth()
        }
    }

    /// Marks CloudKit import activity as ongoing and (re)arms a debounce that
    /// clears `isImportingFromCloud` after a short quiet period.
    ///
    /// `NSPersistentCloudKitContainer` posts only a single, near-instant `import`
    /// event, but the records it pulls keep streaming into the store for much
    /// longer — Apple notes a first import "can take minutes, or longer" (TN3163) —
    /// generating a continuous flow of `NSPersistentStoreRemoteChange` notifications.
    /// Clearing the flag on the brief event boundary made the "Syncing from iCloud…"
    /// overlay flash for a single frame (or never paint at all). Keeping it set
    /// until that activity quiets keeps the overlay visible for the whole import.
    func noteCloudImportActivity() {
        // A device that holds its data locally gets `setup`/`import` events on
        // every launch, which are just noise. Show the overlay only during the
        // first download into a fresh store (a new device, or after Reset Local Cache).
        guard isFirstDownload else { return }
        isImportingFromCloud = true
        cloudImportDebounceTask?.cancel()
        cloudImportDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            } catch {
                return  // cancelled by newer activity
            }
            self?.isImportingFromCloud = false
        }
    }

    /// A burst of remote-change notifications has gone quiet. Core Data posts
    /// one for every write to the store, this device's own saves included, so
    /// it proves nothing about iCloud: it doesn't stamp a sync, clear the
    /// error, zero the waiting count or cancel the save's offline check. Only
    /// a successful import or export event does (`handleSuccessfulCloudKitEvent`).
    func handleRemoteChange() {
        // If an import is in flight, this remote change is part of its incoming
        // stream — keep the "Syncing from iCloud…" overlay alive until it quiets.
        if isImportingFromCloud {
            noteCloudImportActivity()
        }
    }

    func handleLocalSave() {
        // Local save occurred - CloudKit will sync automatically
        pendingSyncCount += 1

        // Only start syncing indicator if not already syncing
        guard !isSyncing else { return }

        isSyncing = true
        syncStartTime = Date()
        currentOperation = "Local save queued for iCloud"
        updateSyncHealth()

        // Cancel any existing timeout task
        syncingTask?.cancel()

        // Wait for either:
        // 1. A successful import or export event (confirming sync completed)
        // 2. A longer timeout (10 seconds) to account for network latency
        // handleSuccessfulCloudKitEvent cancels this task if sync completes
        syncingTask = Task { [weak self] in
            // Use longer timeout for more accurate sync status
            do {
                try await Task.sleep(for: self?.syncTimeout ?? TimeoutConstants.defaultSyncTimeout)
                guard !Task.isCancelled else { return }
            } catch is CancellationError {
                return  // Task was cancelled — sync completed or new save arrived
            } catch {
                return
            }
            guard let self, self.isSyncing else { return }

            // Check if we're online - if not, don't mark as successful
            if !self.isNetworkAvailable {
                self.isSyncing = false
                self.currentOperation = nil
                self.lastOperation = "Sync paused: waiting for network"
                self.lastOperationDate = Date()
                self.recordSyncError(
                    "You're offline. Your changes are saved on this device and send to iCloud "
                        + "when you're back online.",
                    detail: nil, kind: .network, persist: false
                )
                self.updateSyncHealth()
                return
            }

            // Timeout reached without remote confirmation. End the spinner and keep
            // the previously known sync timestamp instead of inferring success.
            self.isSyncing = false
            self.pendingSyncCount = 0
            self.currentOperation = nil
            self.lastOperation = "Sync timed out awaiting confirmation"
            self.lastOperationDate = Date()
            self.updateSyncHealth()
        }
    }

    // MARK: - CloudKit Event Handler

    /// Handles NSPersistentCloudKitContainer sync event notifications.
    /// These events provide precise success/failure information about setup, import,
    /// and export operations — more reliable than inferring sync state from
    /// NSManagedObjectContextDidSave + NSPersistentStoreRemoteChange alone.
    ///
    /// Called with pre-extracted values from the notification to avoid Sendable issues.
    func handleCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        isFinished: Bool,
        succeeded: Bool,
        error: (any Error)?,
        startDate: Date,
        storeIdentifier: String? = nil
    ) {
        // Events fire twice: once when started (isFinished == false) and once when finished
        guard isFinished else {
            // Event is still in progress — ensure syncing indicator is on
            if !isSyncing {
                isSyncing = true
                syncStartTime = Date()
            }
            if currentOperation != "CloudKit event in progress" {
                currentOperation = "CloudKit event in progress"
            }
            if type == .setup || type == .import {
                noteCloudImportActivity()
            }
            updateSyncHealth()
            return
        }

        let typeDescription = Self.eventTypeName(type)
        if currentOperation != nil { currentOperation = nil }
        // Don't clear `isImportingFromCloud` on the event boundary — the brief
        // event is finished but the record stream it started keeps arriving.
        // Re-arm the debounce so the overlay rides the incoming changes and
        // clears only once they actually quiet.
        if type == .setup || type == .import {
            noteCloudImportActivity()
        }

        let store = syncedStore(forIdentifier: storeIdentifier)
        storeHealth.recordFinishedEvent(store: store, type: type, succeeded: succeeded, error: error)

        if succeeded {
            handleSuccessfulCloudKitEvent(
                type: type, store: store, typeDescription: typeDescription,
                startDate: startDate, storeIdentifier: storeIdentifier
            )
        } else {
            handleFailedCloudKitEvent(
                type: type, store: store,
                typeDescription: "\(store.displayName) \(typeDescription.lowercased())", error: error,
                startDate: startDate
            )
        }

        updateSyncHealth()
    }

    // MARK: - CloudKit Event Sub-handlers

    /// A successful import or export is the one thing that says sync worked:
    /// it stamps the sync, clears the error, the waiting count and the save's
    /// offline check, and lets a store that had stopped count as syncing again.
    private func handleSuccessfulCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        store: SyncedStore,
        typeDescription: String,
        startDate: Date,
        storeIdentifier: String?
    ) {
        Self.logger.debug("CloudKit \(typeDescription) succeeded")
        SyncEventLogger.shared.log("cloudkit", status: "success", message: Self.historyLine(succeeded: type))

        // A setup that succeeds says nothing about a delegate that died (TN3164),
        // and isn't a sync; it only ends the spinner its start turned on.
        guard type != .setup else {
            if isSyncing { isSyncing = false }
            updateSyncHealth()
            return
        }

        clearMirroringStopped(by: store, eventStartedAt: startDate)

        // Per store: when an import last caught it up, and how far its history
        // has been exported (the bound for purging it).
        recordWatermark(type: type, startDate: startDate, storeIdentifier: storeIdentifier)

        if type == .import {
            // Arms the dedup cycle; the history processor's report decides what,
            // if anything, it sweeps (see the coordinator).
            DeduplicationCoordinator.shared.requestDeduplicationAfterImport()
            finishFirstDownloadIfNeeded(importedStoreIdentifier: storeIdentifier)
        }

        let now = Date()
        recordSuccessfulSync(at: now)
        let operation = "\(typeDescription) completed"
        if lastOperation != operation { lastOperation = operation }
        lastOperationDate = now
        clearSyncErrorInMemory()
        if pendingSyncCount != 0 { pendingSyncCount = 0 }
        retryLogic.resetRetryCount()

        syncingTask?.cancel()
        syncingTask = nil
        if isSyncing { isSyncing = false }
    }

    // MARK: - Persisted sync state

    /// Records a successful sync: the observable date moves at once, the
    /// stored error key is removed only if one is stored, and the defaults
    /// copy of the date — read only at the next launch — is written at most
    /// once a minute (plus on background / quit). The first success of a
    /// session is written straight away, so a device's first-ever sync is
    /// on disk before anything could lose it.
    func recordSuccessfulSync(at date: Date, persistNow: Bool = false) {
        lastSuccessfulSync = date
        let defaults = UserDefaults.standard
        if defaults.object(forKey: UserDefaultsKeys.cloudKitLastSyncError) != nil
            || defaults.object(forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind) != nil {
            Self.removePersistedSyncError(from: defaults)
        }
        unpersistedSyncDate = date
        guard !persistNow, syncDatePersistedAt != nil else {
            flushPersistedSyncDate()
            return
        }
        guard syncDatePersistTask == nil else { return }
        syncDatePersistTask = Task { [weak self] in
            try? await Task.sleep(for: Self.syncDatePersistInterval)
            guard !Task.isCancelled else { return }
            self?.flushPersistedSyncDate()
        }
    }

    /// Writes a pending `lastSuccessfulSync` to UserDefaults now.
    func flushPersistedSyncDate() {
        syncDatePersistTask?.cancel()
        syncDatePersistTask = nil
        guard let date = unpersistedSyncDate else { return }
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        syncDatePersistedAt = date
        unpersistedSyncDate = nil
    }

    /// Flushes the pending date when the app backgrounds or quits, so the
    /// next launch reads the same value it would have with write-through.
    func observeLifecycleForSyncDateFlush() {
        #if os(iOS)
        let names: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification
        ]
        #elseif os(macOS)
        let names: [Notification.Name] = [
            NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification
        ]
        #else
        let names: [Notification.Name] = []
        #endif
        lifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushPersistedSyncDate() }
            }
        }
    }

    private func handleFailedCloudKitEvent(
        type: NSPersistentCloudKitContainer.EventType,
        store: SyncedStore,
        typeDescription: String,
        error: (any Error)?,
        startDate: Date
    ) {
        recordEventFailure(type: type, store: store, typeDescription: typeDescription, error: error)
        if let error {
            CloudKitConfigurationService.storeError(error, retryCount: retryLogic.retryAttempt)
            if Self.marksMirroringDead(type: type, error: error) {
                // Dated by the failed event: a success that began after it says the delegate works.
                markMirroringStopped(by: store, at: startDate)
            }
        }
        lastOperation = "\(typeDescription) failed"
        lastOperationDate = Date()
        if isSyncing { isSyncing = false }
        syncingTask?.cancel()
        syncingTask = nil
        if type != .setup {
            scheduleRetry()
        }
    }
}
