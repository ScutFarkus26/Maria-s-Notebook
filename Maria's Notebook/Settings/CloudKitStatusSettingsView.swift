import SwiftUI
import SwiftData

struct CloudKitStatusSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    private var isCloudKitEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
    }
    
    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
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
            // Check if there's an error description indicating a fallback occurred
            if let errorDescription = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription),
               !errorDescription.isEmpty {
                return "⚠️ CloudKit sync failed to initialize. Your data is stored locally and will NOT sync across devices. Check your iCloud account and network connection, then restart the app."
            } else {
                return "iCloud sync is enabled but requires an app restart to take effect."
            }
        } else {
            return "Your data is stored locally on this device only. Enable iCloud sync to keep your data synchronized across devices."
        }
    }
}

#Preview {
    CloudKitStatusSettingsView()
}



