import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct DebugToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var showDannyResetConfirm: Bool
    @Binding var showPurgeLegacyWorkConfirm: Bool
    @State private var showResetConfirm = false
    let onScanAndQueue: () -> Void
    let onConsolidate: () -> Void
    
    private func statusText(isEnabled: Bool, isActive: Bool) -> String {
        if isActive {
            return "CloudKit active and syncing"
        } else if isEnabled {
            return "CloudKit enabled (restart required)"
        } else {
            return "CloudKit disabled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Danger Zone
            SettingsGroup(title: "Danger Zone", systemImage: "exclamationmark.triangle.fill") {
                Button(role: .destructive) {
                    showDannyResetConfirm = true
                } label: {
                    Label("Delete Lesson & Work History for Danny + Lil Dan D", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                #if DEBUG
                Button(role: .destructive) {
                    showPurgeLegacyWorkConfirm = true
                } label: {
                    Label("Purge Legacy WorkModel Data", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                #endif
            }

            // CloudKit Settings
            SettingsGroup(title: "CloudKit Sync", systemImage: "icloud") {
                let isEnabled = UserDefaults.standard.bool(forKey: MariasToolboxApp.enableCloudKitKey)
                let isActive = UserDefaults.standard.bool(forKey: MariasToolboxApp.cloudKitActiveKey)
                
                Toggle(
                    "Enable CloudKit Sync",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { 
                            UserDefaults.standard.set($0, forKey: MariasToolboxApp.enableCloudKitKey)
                        }
                    )
                )
                .help("Enable CloudKit to sync data across devices. Requires app restart to take effect.")
                
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Color.green : (isEnabled ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)
                    Text(statusText(isEnabled: isEnabled, isActive: isActive))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                
                // Reset & Force Sync button
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset Local Database & Force CloudKit Sync", systemImage: "arrow.clockwise.icloud")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Deletes local database and forces sync from CloudKit. App will restart automatically.")
                .padding(.top, 8)
                .alert("Reset Local Database?", isPresented: $showResetConfirm) {
                    Button("Reset & Restart", role: .destructive) {
                        do {
                            try MariasToolboxApp.resetLocalDatabaseAndForceCloudKitSync()
                            #if os(macOS)
                            NSApplication.shared.terminate(nil)
                            #else
                            exit(0)
                            #endif
                        } catch {
                            print("Failed to reset database: \(error)")
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all local data and force the app to sync from CloudKit. The app will restart automatically. Make sure CloudKit has your data before doing this!")
                }
                
                Text("CloudKit sync allows your data to be synchronized across all your devices. Check the console logs on app launch to verify CloudKit is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                // CloudKit Status & Record Counts
                Divider()
                    .padding(.vertical, 8)
                
                CloudKitStatusView()
            }

            // Smart Planning (Backfill / Catch Up)
            SettingsGroup(title: "Smart Planning", systemImage: "lightbulb.max") {
                HStack(alignment: .top, spacing: 16) {
                    // 1. Scan & Queue
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            onScanAndQueue()
                        } label: {
                            Label("Scan & Queue 'On Deck' Lessons", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)

                        Text("Scans incomplete work and queues the next lesson. Automatically groups students needing the same lesson.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // 2. Consolidate
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            onConsolidate()
                        } label: {
                            Label("Consolidate 'On Deck' Items", systemImage: "square.on.square.dashed")
                        }
                        .buttonStyle(.bordered)

                        Text("Merges separate cards for the same lesson into one group card in the Inbox.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

