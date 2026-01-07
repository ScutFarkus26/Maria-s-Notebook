import SwiftUI
import SwiftData
import EventKit

/// Settings view for configuring Reminder sync with Apple's Reminders app.
public struct ReminderSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var syncService: ReminderSyncService
    @State private var selectedListName: String = ""
    @State private var availableLists: [String] = []
    @State private var isRefreshing: Bool = false
    @State private var lastSyncStatus: String? = nil
    
    public init() {
        // Initialize without a modelContext; real context is set in onAppear
        // Using try? to gracefully handle any schema issues that might prevent container creation
        let tempContext: ModelContext? = {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: AppSchema.schema, configurations: config) else {
                // If container creation fails, we'll use nil and set it properly in onAppear
                return nil
            }
            return container.mainContext
        }()
        _syncService = StateObject(wrappedValue: ReminderSyncService(modelContext: tempContext))
    }
    
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
        Form {
            Section("Reminder Sync") {
                if needsAuthorization {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminder access is required to sync reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        if isRefreshing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Requesting access...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Request Access") {
                                Task {
                                    await requestAccess()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if let status = lastSyncStatus {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(status.contains("Error") || status.contains("Failed") ? .red : .green)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if !availableLists.isEmpty {
                            Picker("Sync from Reminders List", selection: $selectedListName) {
                                Text("None (Disable Sync)").tag("")
                                ForEach(availableLists, id: \.self) { listName in
                                    Text(listName).tag(listName)
                                }
                            }
                            .onChange(of: selectedListName) { _, newValue in
                                syncService.syncListName = newValue.isEmpty ? nil : newValue
                            }
                            
                            HStack {
                                Button("Refresh Lists") {
                                    Task {
                                        await loadAvailableLists()
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Sync Now") {
                                    Task {
                                        await syncReminders()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedListName.isEmpty || isRefreshing)
                            }
                        } else {
                            Button("Load Reminders Lists") {
                                Task {
                                    await loadAvailableLists()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if let status = lastSyncStatus {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(status.contains("Error") || status.contains("Failed") ? .red : .secondary)
                        }
                        
                        Text("Reminders from the selected list will appear in your Today view. You can manually sync or reminders will sync when you add a new reminder to the selected list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            // Update syncService with real modelContext
            syncService.modelContext = modelContext
            selectedListName = syncService.syncListName ?? ""
            Task {
                await loadAvailableLists()
            }
        }
    }
    
    private func requestAccess() async {
        await MainActor.run {
            isRefreshing = true
            lastSyncStatus = nil
        }
        
        do {
            let granted = try await syncService.requestAuthorization()
            await MainActor.run {
                if granted {
                    lastSyncStatus = "Access granted! Loading reminder lists..."
                    isRefreshing = false
                } else {
                    lastSyncStatus = "Access was denied. Please enable it in System Settings > Privacy & Security > Reminders."
                    isRefreshing = false
                }
            }
            
            if granted {
                await loadAvailableLists()
            }
        } catch {
            await MainActor.run {
                lastSyncStatus = "Failed to request access: \(error.localizedDescription)"
                isRefreshing = false
            }
        }
    }
    
    private func loadAvailableLists() async {
        await MainActor.run {
            isRefreshing = true
        }
        
        let lists = await MainActor.run {
            syncService.getAvailableReminderLists()
        }
        
        await MainActor.run {
            availableLists = lists
            isRefreshing = false
            if lastSyncStatus?.contains("Loading") == true {
                lastSyncStatus = nil
            }
        }
    }
    
    private func syncReminders() async {
        await MainActor.run {
            isRefreshing = true
            lastSyncStatus = "Syncing..."
        }
        
        do {
            try await syncService.syncReminders()
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

#Preview {
    ReminderSyncSettingsView()
        .previewEnvironment()
}

