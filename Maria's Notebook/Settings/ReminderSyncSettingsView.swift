import SwiftUI
import SwiftData
import EventKit

/// Settings view for configuring Reminder sync with Apple's Reminders app.
public struct ReminderSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var syncService: ReminderSyncService
    @State private var selectedListIdentifier: String = ""
    @State private var availableLists: [ReminderSyncService.ReminderListInfo] = []
    @State private var isRefreshing: Bool = false
    @State private var lastSyncStatus: String?

    public init() {
        // Use the shared instance
        _syncService = State(wrappedValue: ReminderSyncService.shared)
    }

    private var needsAuthorization: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return syncService.authorizationStatus != EKAuthorizationStatus.fullAccess
        } else {
            return syncService.authorizationStatus == EKAuthorizationStatus.notDetermined ||
                   syncService.authorizationStatus == EKAuthorizationStatus.denied ||
                   syncService.authorizationStatus == EKAuthorizationStatus.restricted
        }
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
                        Picker("Sync from Reminders List", selection: $selectedListIdentifier) {
                            Text("None (Disable Sync)").tag("")
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
                            refreshLabel: "Refresh Lists",
                            isSyncDisabled: selectedListIdentifier.isEmpty,
                            isRefreshing: isRefreshing,
                            onRefresh: { Task { await loadAvailableLists() } },
                            onSync: { Task { await syncReminders() } }
                        )

                        LastSyncView(lastSync: syncService.lastSuccessfulSync)
                    } else {
                        Button("Load Reminders Lists") {
                            Task { await loadAvailableLists() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let status = lastSyncStatus {
                        StatusMessageView(message: status)
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
            // Update shared syncService with real modelContext
            syncService.modelContext = modelContext
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
                lastSyncStatus = "Access granted! Loading reminder lists..."
                isRefreshing = false
                await loadAvailableLists()
            } else {
                lastSyncStatus = "Access was denied."
                    + " Please enable it in System Settings > Privacy & Security > Reminders."
                isRefreshing = false
            }
        } catch {
            lastSyncStatus = "Failed to request access: \(error.localizedDescription)"
            isRefreshing = false
        }
    }
    
    private func loadAvailableLists() async {
        isRefreshing = true
        let lists = syncService.getAvailableReminderListsWithIdentifiers()
        availableLists = lists
        isRefreshing = false
        if lastSyncStatus?.contains("Loading") == true {
            lastSyncStatus = nil
        }
    }
    
    private func syncReminders() async {
        isRefreshing = true
        lastSyncStatus = "Syncing..."

        do {
            // Use force: true to bypass throttle for explicit user action
            try await syncService.syncReminders(force: true)
            lastSyncStatus = "Sync completed successfully"
            isRefreshing = false
        } catch {
            lastSyncStatus = "Sync failed: \(error.localizedDescription)"
            isRefreshing = false
        }
    }
}

#Preview {
    ReminderSyncSettingsView()
        .previewEnvironment()
}
