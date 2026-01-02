import SwiftUI
import SwiftData

struct CloudKitStatusSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    private var isCloudKitEnabled: Bool {
        UserDefaults.standard.bool(forKey: MariasToolboxApp.enableCloudKitKey)
    }
    
    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: MariasToolboxApp.cloudKitActiveKey)
    }
    
    private var containerID: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "Unknown"
        return "iCloud.\(bundleID)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.headline)
            }
            
            // Status Description
            Text(statusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            if isCloudKitEnabled || isCloudKitActive {
                Divider()
                
                // Container Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Container ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(containerID)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private var statusColor: Color {
        if isCloudKitActive {
            return .green
        } else if isCloudKitEnabled {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var statusText: String {
        if isCloudKitActive {
            return "iCloud Sync Active"
        } else if isCloudKitEnabled {
            return "iCloud Sync Enabled (Restart Required)"
        } else {
            return "iCloud Sync Disabled"
        }
    }
    
    private var statusDescription: String {
        if isCloudKitActive {
            return "Your data is syncing with iCloud. Changes will sync across your devices."
        } else if isCloudKitEnabled {
            return "iCloud sync is enabled but requires an app restart to take effect."
        } else {
            return "Your data is stored locally on this device only. Enable iCloud sync to keep your data synchronized across devices."
        }
    }
}

#Preview {
    CloudKitStatusSettingsView()
}

