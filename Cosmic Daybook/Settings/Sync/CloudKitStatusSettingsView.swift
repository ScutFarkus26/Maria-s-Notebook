import SwiftUI
import CoreData

struct CloudKitStatusSettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var isSyncDetailsExpanded = false
    @AppStorage(UserDefaultsKeys.enableCloudKitSync) private var isCloudKitEnabled = true
    @State private var showingTurnOffConfirmation = false

    /// The three newest logged problems, decoded when the log changes rather than on every redraw.
    @State private var recentErrorLogs: [CloudKitConfigurationService.ErrorLogEntry] = []
    @AppStorage(UserDefaultsKeys.cloudKitErrorLog) private var errorLogData: Data?

    private var syncService: CloudKitSyncStatusService { dependencies.cloudKitSyncStatusService }

    // Written by the launch that opened the store; @AppStorage so the card
    // follows it rather than reading UserDefaults once per redraw.
    @AppStorage(UserDefaultsKeys.cloudKitActive) private var isCloudKitActive = false

    private func loadRecentErrorLogs() {
        recentErrorLogs = Array(CloudKitConfigurationService.getErrorLogs().suffix(3).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Toggle("Sync with iCloud", isOn: syncToggle)

            if isCloudKitEnabled != isCloudKitActive {
                Text("Takes effect the next time you open the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if syncService.mirroringDelegateFailed {
                SyncStoppedBanner(advice: SyncStoppedAdvice.make(health: syncService.storeHealth))
            }

            // A setup found no ready iCloud account: nothing goes into the
            // classroom share until it's ready, or with none, until the app is
            // reopened (bug hunt 2026-10-09, #2).
            if let hold = syncService.shareFilingHold {
                Label(hold.message, systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Status Indicator Row
            HStack(spacing: 10) {
                SyncStatusIndicator(health: syncService.syncHealth)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text(statusText)
                        .font(.headline)

                    if isCloudKitActive, let lastSync = syncService.lastSuccessfulSync {
                        Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Sync Now Button
                if isCloudKitActive {
                    Button {
                        Task {
                            await syncService.syncNow()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .spinning(while: syncService.isSyncing)
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncService.isSyncing)
                    .help("Sync now")
                    .accessibilityLabel("Sync now")
                    // Only announce a value while syncing — a momentary button
                    // carries no value at rest ("Idle" is noise for VoiceOver).
                    .accessibilityValue(syncService.isSyncing ? "Syncing" : "")
                }
            }

            // Status Description
            Text(statusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isCloudKitActive {
                syncDetailsSection
            }

            if !recentErrorLogs.isEmpty {
                recentErrorsSection
            }

            // Error Display
            if case .error(let message) = syncService.syncHealth {
                // A stopped store clears only when that store next succeeds;
                // dismissing would just hide it.
                SyncErrorRow(
                    message: message,
                    details: errorRowDetails,
                    canDismiss: syncService.storeHealth.mostSevereFailure?.severity != .stopped,
                    dismiss: syncService.clearError
                )
            }
        }
        .onAppear(perform: loadRecentErrorLogs)
        .onChange(of: errorLogData) { loadRecentErrorLogs() }
        .confirmationDialog(
            "Turn off iCloud sync?",
            isPresented: $showingTurnOffConfirmation,
            titleVisibility: .visible
        ) {
            Button("Turn off sync", role: .destructive) {
                isCloudKitEnabled = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "From the next time you open the app, this device stops syncing. Your notebook stays "
                + "here, but changes you make won't reach your other devices or your assistant, and "
                + "theirs won't reach you, until you turn sync back on."
            )
        }
    }

    /// Turning sync on applies at once; turning it off asks first.
    private var syncToggle: Binding<Bool> {
        Binding(
            get: { isCloudKitEnabled },
            set: { newValue in
                if newValue {
                    isCloudKitEnabled = true
                } else {
                    showingTurnOffConfirmation = true
                }
            }
        )
    }

    private var syncDetailsSection: some View {
        DisclosureGroup("Details", isExpanded: $isSyncDetailsExpanded) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                LabeledContent("Internet", value: syncService.isNetworkAvailable ? "Connected" : "Not connected")
                LabeledContent("iCloud account", value: syncService.isICloudAvailable ? "Signed in" : "Not available")
                LabeledContent("Right now", value: rightNowText)
                LabeledContent("Changes waiting to send", value: "\(syncService.pendingLocalChanges)")
                if let lastOperationDate = syncService.lastOperationDate {
                    LabeledContent(
                        "Last activity",
                        value: lastOperationDate.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                // What iCloud said about the problem the status line names in
                // plain words (a stopped store's is under the red row's Details).
                if syncService.syncHealth == .warning, let failure = syncService.storeHealth.mostSevereFailure {
                    Text(failure.details)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.footnote)
            .padding(.top, AppTheme.Spacing.verySmall)
        }
        .padding(.top, AppTheme.Spacing.xsmall)
    }

    private var recentErrorsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            Text("Recent sync problems")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(recentErrorLogs.enumerated()), id: \.offset) { _, log in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text(SyncProblemCopy.title(log.category))
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                        .lineLimit(3)

                    Text(SyncProblemCopy.advice(log.category))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TechnicalDetailsDisclosure(details: SyncProblemCopy.details(log))
                }
                .padding(AppTheme.Spacing.verySmall)
                .surface(
                    UIConstants.CornerRadius.small,
                    fill: AppColors.destructive.opacity(UIConstants.OpacityConstants.subtle)
                )
            }
        }
        .padding(.top, AppTheme.Spacing.xsmall)
    }

    private var statusText: String {
        if isCloudKitActive {
            switch syncService.syncHealth {
            case .syncing: return "Syncing…"
            case .healthy, .unknown: return "iCloud sync is on"
            case .warning: return "iCloud sync is having trouble"
            case .error: return "Sync problem"
            case .offline:
                return syncService.isNetworkAvailable && syncService.isICloudSignedOut
                    ? "iCloud isn't available" : "Offline"
            }
        } else if isCloudKitEnabled {
            return "iCloud sync isn't running"
        } else {
            return "iCloud sync is off"
        }
    }

    private var statusDescription: String {
        if isCloudKitActive {
            switch syncService.syncHealth {
            case .syncing:
                return "Sending and receiving your latest changes…"
            case .healthy, .unknown:
                return "Your notebook is kept in iCloud. New changes reach your other devices on their own."
            case .warning:
                if let failure = syncService.storeHealth.mostSevereFailure {
                    return failure.message
                }
                return "Sync is still working, but it's slower than usual or had a hiccup."
                    + " Your notebook is safe on this device."
            case .error:
                return "There was a problem syncing with iCloud. Your notebook is safe on this device."
            case .offline:
                return offlineDescription
            }
        } else if isCloudKitEnabled {
            if let errorDescription = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription),
               !errorDescription.isEmpty {
                return "iCloud sync couldn't start, so changes on this device aren't reaching your other devices."
                    + " Check that you're signed in to iCloud in \(SystemSettingsApp.name) and online,"
                    + " then reopen the app."
                    + " If it keeps happening, open Troubleshooting."
            } else {
                return "iCloud sync starts the next time you open the app."
            }
        } else {
            return "Your notebook is kept on this device only."
                + " Turn on iCloud sync to have it on all your devices."
        }
    }

    private var offlineDescription: String {
        if !syncService.isNetworkAvailable && !syncService.isICloudAvailable {
            return "No internet connection, and iCloud isn't available."
                + " Changes are saved on this device and sync when both are back."
        } else if !syncService.isNetworkAvailable {
            return "No internet connection. Changes are saved on this device and sync when you're back online."
        } else if !syncService.isICloudAvailable {
            return "iCloud isn't available. Sign in to iCloud in \(SystemSettingsApp.name) to sync your notebook."
        } else {
            return "Can't reach iCloud right now. Changes are saved on this device and sync when it's reachable again."
        }
    }

    /// The raw text behind the red error row: a stopped store's server
    /// message, else the last sync error's.
    private var errorRowDetails: String {
        if let failure = syncService.storeHealth.mostSevereFailure, failure.severity == .stopped {
            return failure.details
        }
        return syncService.lastSyncErrorDetail ?? ""
    }

    /// What sync is doing now, in plain words; a scheduled retry reads as "Trying again soon".
    private var rightNowText: String {
        if syncService.hasPendingRetry { return "Trying again soon" }
        if syncService.isSyncing || syncService.currentOperation != nil { return "Syncing" }
        return "Nothing in progress"
    }
}

/// Plain words for a logged sync problem (the log's own names are iCloud's).
private enum SyncProblemCopy {
    /// A short name for the kind of problem.
    static func title(_ category: CloudKitConfigurationService.ErrorCategory) -> String {
        switch category {
        case .authentication: return "iCloud sign-in"
        case .network: return "Internet connection"
        case .quota: return "iCloud storage is full"
        case .conflict: return "Two devices disagreed"
        case .schema: return "The app needs an update"
        case .unknown: return "Something went wrong"
        }
    }

    /// The raw error behind a logged problem, for its Details.
    static func details(_ log: CloudKitConfigurationService.ErrorLogEntry) -> String {
        var text = log.errorMessage
        if let domain = log.errorDomain, let code = log.errorCode {
            text += " [\(domain) (\(code))]"
        }
        return text
    }

    /// What to do about a logged sync problem.
    static func advice(_ category: CloudKitConfigurationService.ErrorCategory) -> String {
        switch category {
        case .authentication: return "Check that you're signed in to iCloud in \(SystemSettingsApp.name)."
        case .network: return "Check your internet connection. Sync tries again on its own."
        case .quota: return "Free up some iCloud storage. Sync tries again on its own."
        case .conflict: return "Keep working. This usually sorts itself out on the next try."
        case .schema: return "Update Cosmic Daybook on all your devices."
        case .unknown: return "Sync tries again on its own. If it keeps happening, reopen the app."
        }
    }
}

/// Animated sync status indicator
struct SyncStatusIndicator: View {
    let health: CloudKitHealthCheck.SyncHealth

    var body: some View {
        ZStack {
            Circle()
                .fill(health.color.opacity(UIConstants.OpacityConstants.moderate))
                .frame(width: 28, height: 28)

            Image(systemName: health.icon)
                .font(.subheadline)
                .foregroundStyle(health.color)
                .spinning(while: health == .syncing)
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct CloudKitStatusSettingsViewPreview: View {
    var body: some View {
        CloudKitStatusSettingsView()
            .previewEnvironment()
    }
}

#Preview {
    CloudKitStatusSettingsViewPreview()
}

/// The red row under the sync status: the error in plain words, the raw
/// text under Details, and Dismiss when dismissing means something.
private struct SyncErrorRow: View {
    let message: String
    let details: String
    let canDismiss: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.destructive)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(6)

                TechnicalDetailsDisclosure(details: details)
            }

            Spacer()

            if canDismiss {
                Button("Dismiss", action: dismiss)
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .padding(AppTheme.Spacing.small)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: AppColors.destructive.opacity(UIConstants.OpacityConstants.light)
        )
    }
}
