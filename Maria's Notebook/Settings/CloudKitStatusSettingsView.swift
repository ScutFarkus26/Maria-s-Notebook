import SwiftUI
import SwiftData
import CloudKit

struct CloudKitStatusSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var iCloudAccountStatus: CKAccountStatus?
    @State private var isCheckingAccount: Bool = false
    
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
                    
                    // Bundle ID for verification
                    Text("Bundle ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text(Bundle.main.bundleIdentifier ?? "Unknown")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                
                // iCloud Account Status
                if let accountStatus = iCloudAccountStatus {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accountStatusColor(accountStatus))
                                .frame(width: 8, height: 8)
                            Text(accountStatusText(accountStatus))
                                .font(.caption)
                        }
                    }
                } else if isCheckingAccount {
                    Divider()
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking iCloud account...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Verify Button and Sync Info
                if isCloudKitActive {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: checkiCloudAccount) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Verify iCloud Account")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        
                        // Sync troubleshooting info
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Troubleshooting")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("If data isn't syncing across devices:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• Verify Container ID matches on all devices")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("• Ensure all devices use the same iCloud account")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("• Check iCloud Drive is enabled in System Settings")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("• Wait a few minutes for initial sync")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .onAppear {
            if isCloudKitActive {
                checkiCloudAccount()
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
            var description = "Your data is syncing with iCloud. Changes will sync across your devices."
            if let accountStatus = iCloudAccountStatus, accountStatus != .available {
                description += "\n⚠️ iCloud account issue detected. See details below."
            }
            return description
        } else if isCloudKitEnabled {
            return "iCloud sync is enabled but requires an app restart to take effect."
        } else {
            return "Your data is stored locally on this device only. Enable iCloud sync to keep your data synchronized across devices."
        }
    }
    
    private func checkiCloudAccount() {
        isCheckingAccount = true
        let container = CKContainer(identifier: containerID)
        container.accountStatus { accountStatus, error in
            DispatchQueue.main.async {
                isCheckingAccount = false
                if let error = error {
                    print("CloudKit: Error checking account status: \(error.localizedDescription)")
                }
                // accountStatus is always provided (non-optional)
                self.iCloudAccountStatus = accountStatus
                #if DEBUG
                print("CloudKit: Account status: \(self.accountStatusText(accountStatus))")
                #endif
            }
        }
    }
    
    private func accountStatusColor(_ status: CKAccountStatus) -> Color {
        switch status {
        case .available:
            return .green
        case .noAccount, .restricted:
            return .red
        case .couldNotDetermine, .temporarilyUnavailable:
            return .orange
        default:
            return .gray
        }
    }
    
    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Signed in and available"
        case .noAccount:
            return "No iCloud account signed in"
        case .restricted:
            return "iCloud account restricted"
        case .couldNotDetermine:
            return "Status unknown"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        default:
            return "Unknown status"
        }
    }
}

#Preview {
    CloudKitStatusSettingsView()
}



