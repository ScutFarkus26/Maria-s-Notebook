import SwiftUI
import OSLog

/// Maintenance card for the Settings → Database tab. Exposes "Reset Local
/// Cache" — the only known recovery path when
/// `NSPersistentCloudKitContainer`'s mirroring delegate fails to initialize
/// (`NSCocoaErrorDomain 134421`, "Never successfully initialized").
///
/// The actual reset can't run while the container is loaded, so the button
/// just arms a UserDefaults flag and asks the user to relaunch. On the next
/// launch, `CoreDataStack.init` sees the flag, deletes the on-disk stores +
/// migration flags, then clears the flag. The container reconstitutes from
/// CloudKit.
struct DatabaseMaintenanceCard: View {
    private static let logger = Logger.app(category: "DatabaseMaintenance")

    @State private var showingResetConfirmation = false
    @State private var showingRelaunchPrompt = false
    @State private var showingInMemoryConfirmation = false
    #if os(macOS)
    @AppStorage(UserDefaultsKeys.allowLocalStoreFallback) private var allowLocalStoreFallback = false
    #endif

    private var isResetArmed: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
    }

    var body: some View {
        SettingsGroup(title: "Maintenance", systemImage: "wrench.and.screwdriver.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reset Local Cache")
                    .font(.subheadline.weight(.semibold))

                Text(
                    "Deletes the local Core Data stores and re-downloads everything from iCloud on the next launch. " +
                    "Use this if iCloud sync is stuck (you'll see a red banner in Data & Sync when that happens) " +
                    "or if you're recovering from a corrupted local database."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your data lives in iCloud and is not affected. Local-only data (if any) will be lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isResetArmed {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Reset will run when you next launch the app.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                        Button("Cancel") {
                            clearPendingResetRequest()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                } else {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Local Cache and Re-sync from iCloud",
                              systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.red)
                }

                Divider()
                    .padding(.vertical, 4)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        #if os(macOS)
                        Toggle("Allow Local Store Fallback", isOn: $allowLocalStoreFallback)
                        Text("If iCloud is unavailable at launch, open a local-only store instead of failing to start.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        #endif

                        Button("Use In-Memory Store on Next Launch") {
                            showingInMemoryConfirmation = true
                        }
                        Text("Diagnostic only: the next launch runs without saving. Your stored data is untouched and returns when you relaunch normally afterward.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    // Style the disclosure label only — .font on the whole group
                    // would cascade into the child Toggle/Button labels.
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Reset local cache?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset on Next Launch", role: .destructive) {
                armResetRequest(source: "Settings.DatabaseMaintenanceCard")
                showingRelaunchPrompt = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "On next launch, the app will delete the local Core Data stores and re-download your data " +
                "from iCloud. This can take several minutes depending on classroom size and network speed."
            )
        }
        .alert("Relaunch the app", isPresented: $showingRelaunchPrompt) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Quit Maria's Notebook (⌘Q on Mac) and reopen it. The reset will run automatically.")
        }
        .confirmationDialog(
            "Use in-memory store next launch?",
            isPresented: $showingInMemoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Use In-Memory Next Launch", role: .destructive) {
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "On the next launch only, the app runs with a temporary in-memory database for " +
                "diagnostics. Nothing you do in that session is saved. Relaunch again afterward " +
                "to return to your real data."
            )
        }
    }

    private func armResetRequest(source: String) {
        let armedAt = Date.now.ISO8601Format()
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
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
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
        Self.logger.info(
            "Cleared pending local cache reset. source=\(source, privacy: .public), armedAt=\(armedAt, privacy: .public)"
        )
    }
}
