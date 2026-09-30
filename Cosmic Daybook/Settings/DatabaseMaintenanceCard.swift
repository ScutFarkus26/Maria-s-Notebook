import SwiftUI
import OSLog

/// Troubleshooting's "If sync gets stuck" card. Offers "Re-download from
/// iCloud" (Reset Local Cache) — the only known recovery path when
/// `NSPersistentCloudKitContainer`'s mirroring delegate fails to initialize
/// (`NSCocoaErrorDomain 134421`, "Never successfully initialized").
///
/// The actual reset can't run while the container is loaded, so the button
/// just arms a UserDefaults flag and asks the user to relaunch. On the next
/// launch, `CoreDataStack.init` sees the flag, deletes the on-disk stores +
/// migration flags, then clears the flag. The container reconstitutes from
/// CloudKit.
struct DatabaseMaintenanceCard: View {
    private static let logger = Logger.databaseMaintenance

    @State private var showingResetConfirmation = false
    @State private var showingRelaunchPrompt = false

    // @AppStorage, not a computed read of UserDefaults, so arming or cancelling
    // redraws the card straight away.
    @AppStorage(UserDefaultsKeys.resetLocalCacheOnLaunch) private var isResetArmed = false
    #if DEBUG
    @State private var showingInMemoryConfirmation = false
    @AppStorage(UserDefaultsKeys.useInMemoryStoreOnce) private var isInMemoryArmed = false
    #endif

    var body: some View {
        SettingsGroup(
            .maintenance,
            footer: "Your notebook lives in iCloud. This throws away this device's copy "
                + "and downloads a fresh one when you next open the app."
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text("If this device stops syncing, or its notebook looks out of date or damaged, re-download it.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if isResetArmed {
                    armedRow(
                        "Your notebook will re-download when you next open the app.",
                        systemImage: "arrow.clockwise.circle.fill",
                        onCancel: clearPendingResetRequest
                    )
                } else {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Re-download from iCloud…", systemImage: "icloud.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(AppColors.destructive)
                }

                #if DEBUG
                Divider()
                    .padding(.vertical, AppTheme.Spacing.xsmall)

                advancedSection
                #endif
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Re-download from iCloud?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-download next time", role: .destructive) {
                armResetRequest(source: "Settings.DatabaseMaintenanceCard")
                showingRelaunchPrompt = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "When you next open the app, this device's copy of your notebook is thrown away and a " +
                "fresh one downloads from iCloud. Changes that haven't reached iCloud yet are lost. " +
                "With a big classroom or a slow connection this can take several minutes."
            )
        }
        .alert("Relaunch the app", isPresented: $showingRelaunchPrompt) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(relaunchInstructions)
        }
        #if DEBUG
        .confirmationDialog(
            "Use in-memory store next launch?",
            isPresented: $showingInMemoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Use In-Memory Next Launch", role: .destructive) {
                isInMemoryArmed = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "On the next launch only, the app runs with a temporary in-memory database for " +
                "diagnostics. Nothing you do in that session is saved. Relaunch again afterward " +
                "to return to your real data."
            )
        }
        #endif
    }

    #if DEBUG
    private var advancedSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                // Developer diagnostic, never shown in a release build.
                if isInMemoryArmed {
                    armedRow(
                        "The next launch will run without saving.",
                        systemImage: "memorychip",
                        onCancel: { isInMemoryArmed = false }
                    )
                } else {
                    Button("Use In-Memory Store on Next Launch") {
                        showingInMemoryConfirmation = true
                    }
                }
                Text(
                    "Diagnostic only: the next launch runs without saving. Your stored data is " +
                    "untouched and returns when you relaunch normally afterward."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, AppTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            // Style the disclosure label only — .font on the whole group
            // would cascade into the child Toggle/Button labels.
            Text("Advanced")
                .font(.subheadline.weight(.semibold))
        }
    }
    #endif

    /// How to quit and reopen, in this platform's words (no ⌘Q on iPhone or iPad).
    private var relaunchInstructions: String {
        #if os(macOS)
        "Quit Cosmic Daybook (⌘Q) and open it again. The download starts on its own."
        #else
        "Close Cosmic Daybook (swipe it away in the app switcher) and open it again. "
            + "The download starts on its own."
        #endif
    }

    /// The orange "this will happen on the next launch" row, with a way to take it back.
    private func armedRow(
        _ message: String,
        systemImage: String,
        onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.warning)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.warning)
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .font(.caption)
                .buttonStyle(.borderless)
        }
        .padding(AppTheme.Spacing.small)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: AppColors.warning.opacity(UIConstants.OpacityConstants.medium),
            style: .continuous
        )
    }

    private func armResetRequest(source: String) {
        let armedAt = Date.now.ISO8601Format()
        let defaults = UserDefaults.standard
        isResetArmed = true
        defaults.set(armedAt, forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.set(source, forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
        Self.logger.warning(
            "Local cache reset armed. source=\(source, privacy: .public), armedAt=\(armedAt, privacy: .public)"
        )
    }

    private func clearPendingResetRequest() {
        let defaults = UserDefaults.standard
        let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
        let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
        isResetArmed = false
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
        Self.logger.info(
            "Cancelled local cache reset. source=\(source, privacy: .public), armedAt=\(armedAt, privacy: .public)"
        )
    }
}
