import SwiftUI
import CoreData
import EventKit

/// Settings view for configuring Calendar sync with Apple's Calendar app.
/// Supports selecting multiple calendars to sync.
public struct CalendarSyncSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    private var syncService: CalendarSyncService { dependencies.calendarSync }
    @State private var selectedCalendarIdentifiers: Set<String> = []
    @State private var availableCalendars: [CalendarSyncService.CalendarInfo] = []
    /// Keeps "No calendars found" from flashing before the first load.
    @State private var hasLoadedCalendars = false
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
                        Text("Choose calendars to sync")
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
                            refreshLabel: "Refresh calendars",
                            isSyncDisabled: selectedCalendarIdentifiers.isEmpty,
                            isRefreshing: isRefreshing,
                            onRefresh: { Task { await loadAvailableCalendars() } },
                            onSync: { Task { await syncCalendarEvents() } }
                        )

                        LastSyncView(lastSync: syncService.lastSuccessfulSync)
                    } else if hasLoadedCalendars {
                        Text("No calendars found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let lastSyncStatus {
                        StatusMessageView(status: lastSyncStatus)
                    }

                    Text(
                        "Events from selected calendars will appear in your Today view."
                        + " Events sync automatically when changes are detected."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            syncService.managedObjectContext = viewContext
            selectedCalendarIdentifiers = Set(syncService.syncCalendarIdentifiers)
            await loadAvailableCalendars()
        }
    }

    private func updateSyncService() {
        let selectedIdentifiers = Array(selectedCalendarIdentifiers)
        let selectedNames = availableCalendars
            .filter { selectedCalendarIdentifiers.contains($0.identifier) }
            .map(\.name)

        syncService.syncCalendarIdentifiers = selectedIdentifiers
        syncService.syncCalendarNames = selectedNames
    }

    private func requestAccess() async {
        isRefreshing = true
        lastSyncStatus = nil

        do {
            let granted = try await syncService.requestAuthorization()
            if granted {
                // Load calendars first, then update status
                await loadAvailableCalendars()
                if availableCalendars.isEmpty {
                    lastSyncStatus = .success("Access granted, but no calendars were found.")
                } else {
                    lastSyncStatus = .success("Access granted. Choose calendars below.")
                }
                isRefreshing = false
            } else {
                lastSyncStatus = .failure("Access is off. Turn it on in \(SystemSettingsApp.privacyPath("Calendars")).")
                isRefreshing = false
            }
        } catch {
            lastSyncStatus = .failure(AppErrorMessages.syncMessage(for: error, service: "Calendar"))
            isRefreshing = false
        }
    }

    private func loadAvailableCalendars() async {
        isRefreshing = true
        let calendars = syncService.getAvailableCalendarsWithIdentifiers()
        availableCalendars = calendars
        hasLoadedCalendars = true
        isRefreshing = false
    }

    private func syncCalendarEvents() async {
        isRefreshing = true
        lastSyncStatus = .info("Syncing…")

        do {
            try await syncService.syncEvents(force: true)
            lastSyncStatus = .success("Synced just now.")
            isRefreshing = false
        } catch {
            lastSyncStatus = .failure(AppErrorMessages.syncMessage(for: error, service: "Calendar"))
            isRefreshing = false
        }
    }
}

/// A row for toggling calendar selection with a checkbox
private struct CalendarToggleRow: View {
    let calendarInfo: CalendarSyncService.CalendarInfo
    let isSelected: Bool
    /// SwiftUI invokes custom binding setters from an actor-isolated, Sendable
    /// closure. The selection is still changed only by this view on the main
    /// actor; the annotation makes that boundary explicit to Swift 6.
    let onToggle: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        #if os(macOS)
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { newValue in
                onToggle(newValue)
            }
        )) {
            HStack(spacing: AppTheme.Spacing.small) {
                if let cgColor = calendarInfo.color {
                    Circle()
                        .fill(Color(cgColor: cgColor))
                        .frame(width: 12, height: 12)
                }
                Text(calendarInfo.name)
            }
        }
        .toggleStyle(.checkbox)
        #else
        Button(action: { onToggle(!isSelected) }, label: {
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
        })
        .buttonStyle(.plain)
        #endif
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct CalendarSyncSettingsViewPreview: View {
    var body: some View {
        CalendarSyncSettingsView()
            .previewEnvironment()
    }
}

#Preview("Calendar Sync Settings") {
    CalendarSyncSettingsViewPreview()
}
