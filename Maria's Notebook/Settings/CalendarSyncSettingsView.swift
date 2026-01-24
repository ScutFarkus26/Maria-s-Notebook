import SwiftUI
import SwiftData
import EventKit

/// Settings view for configuring Calendar sync with Apple's Calendar app.
/// Supports selecting multiple calendars to sync.
public struct CalendarSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncService = CalendarSyncService.shared
    @State private var selectedCalendarIdentifiers: Set<String> = []
    @State private var availableCalendars: [CalendarSyncService.CalendarInfo] = []
    @State private var isRefreshing: Bool = false
    @State private var lastSyncStatus: String? = nil

    public init() {}

    private var needsAuthorization: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return syncService.authorizationStatus != .fullAccess
        } else {
            return syncService.authorizationStatus == .notDetermined ||
                   syncService.authorizationStatus == .denied ||
                   syncService.authorizationStatus == .restricted
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            if needsAuthorization {
                AuthorizationRequestSection(
                    serviceName: "Calendar",
                    description: "Calendar access is required to show events in your Today view.",
                    settingsPath: "Calendars",
                    isRefreshing: isRefreshing,
                    statusMessage: lastSyncStatus,
                    onRequestAccess: {
                        Task { await requestAccess() }
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                    if !availableCalendars.isEmpty {
                        Text("Select calendars to sync:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Multi-select list of calendars
                        ForEach(availableCalendars) { calInfo in
                            CalendarToggleRow(
                                calendarInfo: calInfo,
                                isSelected: selectedCalendarIdentifiers.contains(calInfo.identifier),
                                onToggle: { isSelected in
                                    if isSelected {
                                        selectedCalendarIdentifiers.insert(calInfo.identifier)
                                    } else {
                                        selectedCalendarIdentifiers.remove(calInfo.identifier)
                                    }
                                    updateSyncService()
                                }
                            )
                        }

                        SyncActionButtons(
                            refreshLabel: "Refresh Calendars",
                            isSyncDisabled: selectedCalendarIdentifiers.isEmpty,
                            isRefreshing: isRefreshing,
                            onRefresh: { Task { await loadAvailableCalendars() } },
                            onSync: { Task { await syncCalendarEvents() } }
                        )

                        LastSyncView(lastSync: syncService.lastSuccessfulSync)
                    } else {
                        Button("Load Calendars") {
                            Task { await loadAvailableCalendars() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let status = lastSyncStatus {
                        StatusMessageView(message: status)
                    }

                    Text("Events from selected calendars will appear in your Today view. Events sync automatically when changes are detected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            syncService.modelContext = modelContext
            selectedCalendarIdentifiers = Set(syncService.syncCalendarIdentifiers)
            Task {
                await loadAvailableCalendars()
            }
        }
    }

    private func updateSyncService() {
        let selectedIdentifiers = Array(selectedCalendarIdentifiers)
        let selectedNames = availableCalendars
            .filter { selectedCalendarIdentifiers.contains($0.identifier) }
            .map { $0.name }

        syncService.syncCalendarIdentifiers = selectedIdentifiers
        syncService.syncCalendarNames = selectedNames
    }

    private func requestAccess() async {
        await MainActor.run {
            isRefreshing = true
            lastSyncStatus = nil
        }

        do {
            let granted = try await syncService.requestAuthorization()
            if granted {
                // Load calendars first, then update status
                await loadAvailableCalendars()
                await MainActor.run {
                    if availableCalendars.isEmpty {
                        lastSyncStatus = "Access granted but no calendars found."
                    } else {
                        lastSyncStatus = "Access granted! Select calendars below."
                    }
                    isRefreshing = false
                }
            } else {
                await MainActor.run {
                    lastSyncStatus = "Access was denied. Please enable it in System Settings > Privacy & Security > Calendars."
                    isRefreshing = false
                }
            }
        } catch {
            await MainActor.run {
                lastSyncStatus = "Failed to request access: \(error.localizedDescription)"
                isRefreshing = false
            }
        }
    }

    private func loadAvailableCalendars() async {
        await MainActor.run {
            isRefreshing = true
        }

        let calendars = await MainActor.run {
            syncService.getAvailableCalendarsWithIdentifiers()
        }

        await MainActor.run {
            availableCalendars = calendars
            isRefreshing = false
            if lastSyncStatus?.contains("Loading") == true {
                lastSyncStatus = nil
            }
        }
    }

    private func syncCalendarEvents() async {
        await MainActor.run {
            isRefreshing = true
            lastSyncStatus = "Syncing..."
        }

        do {
            try await syncService.syncEvents(force: true)
            await MainActor.run {
                lastSyncStatus = "Sync completed successfully"
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                lastSyncStatus = "Sync failed: \(error.localizedDescription)"
                isRefreshing = false
            }
        }
    }
}

/// A row for toggling calendar selection with a checkbox
private struct CalendarToggleRow: View {
    let calendarInfo: CalendarSyncService.CalendarInfo
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button(action: { onToggle(!isSelected) }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                // Calendar color indicator
                if let cgColor = calendarInfo.color {
                    Circle()
                        .fill(Color(cgColor: cgColor))
                        .frame(width: 12, height: 12)
                }

                Text(calendarInfo.name)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CalendarSyncSettingsView()
        .previewEnvironment()
}
