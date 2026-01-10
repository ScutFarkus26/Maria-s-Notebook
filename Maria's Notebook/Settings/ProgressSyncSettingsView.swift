import SwiftUI
import SwiftData

struct ProgressSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    @State private var syncError: String? = nil
    @State private var lastSyncResult: (presentationsUpdated: Int, mastered: Int)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update all students' progress pages by syncing lesson presentations and completed work.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let result = lastSyncResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Updated \(result.presentationsUpdated) presentations, marked \(result.mastered) as mastered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button(action: {
                Task {
                    await syncProgress()
                }
            }) {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isSyncing ? "Syncing..." : "Sync Progress Now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
            
            if let error = syncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    @MainActor
    private func syncProgress() async {
        isSyncing = true
        syncMessage = nil
        syncError = nil
        lastSyncResult = nil
        
        do {
            let result = try LifecycleService.syncAllStudentProgress(context: modelContext)
            lastSyncResult = result
            syncMessage = "Successfully synced progress: \(result.presentationsUpdated) presentations updated, \(result.mastered) marked as mastered"
        } catch {
            syncError = "Failed to sync progress: \(error.localizedDescription)"
        }
        
        isSyncing = false
    }
}
