import SwiftUI
import CoreData
import EventKit

/// Settings view for configuring CDReminder sync with Apple's Reminders app.
/// The list choice, Off included, is this device's own.
public struct ReminderSyncSettingsView: View {
    @Environment(\.dependencies) private var dependencies
    private var syncService: ReminderSyncService { dependencies.reminderSync }
    @State private var selectedListIdentifier: String = ""
    @State private var availableLists: [ReminderSyncService.ReminderListInfo] = []
    /// Keeps "No reminder lists found" from flashing before the first load.
    @State private var hasLoadedLists = false
    @State private var isRefreshing: Bool = false
    @State private var lastSyncStatus: StatusMessage?

    public init() {}

    private var needsAuthorization: Bool {
        syncService.authorizationStatus != EKAuthorizationStatus.fullAccess
    }

    private var footnote: String {
        if !syncService.isListConfigured {
            return "This device doesn't read your Reminders. Reminders already in your notebook stay,"
                + " and your other devices keep their own choice."
        }
        return "Reminders from this list show on Today and update when they change in Reminders."
            + " This choice is for this device only."
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            if needsAuthorization {
                AuthorizationRequestSection(
                    serviceName: "Reminders",
                    description: "Reminder access is required to sync reminders.",
                    settingsPath: "Reminders",
                    isRefreshing: isRefreshing,
                    statusMessage: lastSyncStatus,
                    onRequestAccess: {
                        Task { await requestAccess() }
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                    if !availableLists.isEmpty {
                        Picker("Show reminders from", selection: $selectedListIdentifier) {
                            Text("Off").tag("")
                            ForEach(availableLists) { listInfo in
                                Text(listInfo.name).tag(listInfo.identifier)
                            }
                        }
                        .onChange(of: selectedListIdentifier) { _, newValue in
                            if newValue.isEmpty {
                                // This device only; the reminders already in the notebook stay.
                                syncService.turnOff()
                            } else if let listInfo = availableLists.first(where: { $0.identifier == newValue }) {
                                syncService.syncListIdentifier = listInfo.identifier
                                syncService.syncListName = listInfo.name
                            }
                        }

                        SyncActionButtons(
                            refreshLabel: "Refresh lists",
                            isSyncDisabled: selectedListIdentifier.isEmpty,
                            isRefreshing: isRefreshing,
                            onRefresh: { Task { await loadAvailableLists() } },
                            onSync: { Task { await syncReminders() } }
                        )

                        LastSyncView(lastSync: syncService.lastSuccessfulSync)
                    } else if hasLoadedLists {
                        Text("No reminder lists found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let lastSyncStatus {
                        StatusMessageView(status: lastSyncStatus)
                    }

                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            // `dependencies.reminderSync` already points the service at My
            // Class's store, and never at the Sample Class's. Pointing it at
            // this view's store here did, when Settings was opened in the
            // Sample Class, and the next sync copied real reminders into it.
            selectedListIdentifier = syncService.syncListIdentifier ?? ""
            await loadAvailableLists()
        }
    }

    private func requestAccess() async {
        isRefreshing = true
        lastSyncStatus = nil

        do {
            let granted = try await syncService.requestAuthorization()
            if granted {
                await loadAvailableLists()
                if availableLists.isEmpty {
                    lastSyncStatus = .success("Access granted, but no lists were found.")
                } else {
                    lastSyncStatus = .success("Access granted. Choose a list below.")
                }
                isRefreshing = false
            } else {
                lastSyncStatus = .failure("Access is off. Turn it on in \(SystemSettingsApp.privacyPath("Reminders")).")
                isRefreshing = false
            }
        } catch {
            lastSyncStatus = .failure(AppErrorMessages.syncMessage(for: error, service: "Reminders"))
            isRefreshing = false
        }
    }

    private func loadAvailableLists() async {
        isRefreshing = true
        let lists = syncService.getAvailableReminderListsWithIdentifiers()
        availableLists = lists
        // A setup saved by list name only (from before identifiers were kept)
        // still shows its list, as the sync reads it.
        if selectedListIdentifier.isEmpty, syncService.syncListIdentifier == nil,
           let name = syncService.syncListName, !name.isEmpty,
           let match = lists.first(where: {
               $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           }) {
            selectedListIdentifier = match.identifier
        }
        hasLoadedLists = true
        isRefreshing = false
    }

    private func syncReminders() async {
        isRefreshing = true
        lastSyncStatus = .info("Syncing…")

        do {
            // Use force: true to bypass throttle for explicit user action
            try await syncService.syncReminders(force: true)
            lastSyncStatus = .success("Synced just now.")
            isRefreshing = false
        } catch {
            lastSyncStatus = .failure(AppErrorMessages.syncMessage(for: error, service: "Reminders"))
            isRefreshing = false
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ReminderSyncSettingsViewPreview: View {
    var body: some View {
        ReminderSyncSettingsView()
            .previewEnvironment()
    }
}

#Preview {
    ReminderSyncSettingsViewPreview()
}
