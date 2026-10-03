import SwiftUI
import CoreData
import EventKit

/// Settings view for configuring CDReminder sync with Apple's Reminders app.
public struct ReminderSyncSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
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
                        Picker("Sync from list", selection: $selectedListIdentifier) {
                            Text("None (don't sync)").tag("")
                            ForEach(availableLists) { listInfo in
                                Text(listInfo.name).tag(listInfo.identifier)
                            }
                        }
                        .onChange(of: selectedListIdentifier) { _, newValue in
                            if newValue.isEmpty {
                                syncService.syncListIdentifier = nil
                                syncService.syncListName = nil
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

                    Text(
                        "Reminders from the selected list will appear in your Today view."
                        + " You can manually sync or reminders will sync automatically when changes are detected."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            // Update shared syncService with real viewContext
            syncService.managedObjectContext = viewContext
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
