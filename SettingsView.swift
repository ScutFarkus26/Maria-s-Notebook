import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Live data for stats
    @Query private var students: [Student]
    @Query private var items: [Item]

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isShowingAlert: Bool = false
    @State private var isConfirmingRestore: Bool = false
    @State private var pendingRestoreURL: URL? = nil

    @State private var lastBackupDescription: String = "Never"

    private var stats: [DatabaseStat] {
        let studentCount = students.count
        let itemCount = items.count
        let storageMB: Double = estimateStorageMB()
        let storageProgress = min(max(storageMB / 500.0, 0.0), 1.0) // pretend 500 MB soft cap
        return [
            DatabaseStat(title: "Students", value: "\(studentCount)", icon: "👩🏽‍🎓", tint: .pink, progress: nil),
            DatabaseStat(title: "Items", value: "\(itemCount)", icon: "📦", tint: .blue, progress: nil),
            DatabaseStat(title: "Storage", value: String(format: "%.0f MB", storageMB), icon: "💾", tint: .purple, progress: storageProgress),
            DatabaseStat(title: "Last Backup", value: lastBackupDescription, icon: "🗂️", tint: .green, progress: nil)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            // Fun horizontal database stats
            DatabaseStatsStrip(stats: stats)
                .frame(maxHeight: 120)

            Text("Backup and Restore")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    restoreBackup()
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
            }

            Text("Export creates a JSON file with your Items and Students. Restore replaces all current data with the file's contents.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "This will replace all current data.",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let url = pendingRestoreURL {
                    performRestore(from: url)
                }
                pendingRestoreURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreURL = nil
            }
        } message: {
            Text("Are you sure you want to restore from backup? This cannot be undone.")
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Backup & Restore
    private func exportBackup() {
        do {
            let data = try BackupManager.makeBackupData(using: modelContext)
#if os(macOS)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = defaultBackupFileName()
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                lastBackupDescription = Self.relativeDateFormatter.localizedString(for: Date(), relativeTo: Date())
                showAlert(title: "Backup Exported", message: "Saved to \(url.lastPathComponent)")
            }
#else
            // TODO: iOS export flow if needed
            lastBackupDescription = Self.relativeDateFormatter.localizedString(for: Date(), relativeTo: Date())
            showAlert(title: "Not Supported", message: "Export is currently supported on macOS only in this build.")
#endif
        } catch {
            showAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func restoreBackup() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pendingRestoreURL = url
            isConfirmingRestore = true
        }
#else
        showAlert(title: "Not Supported", message: "Restore is currently supported on macOS only in this build.")
#endif
    }

    private func performRestore(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try BackupManager.restore(from: data, using: modelContext)
            showAlert(title: "Restore Complete", message: "Successfully restored from \(url.lastPathComponent)")
            lastBackupDescription = "Restored " + Self.relativeDateFormatter.localizedString(for: Date(), relativeTo: Date())
        } catch {
            showAlert(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isShowingAlert = true
    }

    private func defaultBackupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "MariasToolbox-Backup-\(formatter.string(from: Date())).json"
    }

    private func estimateStorageMB() -> Double {
        // Placeholder estimate based on row counts; replace with real measurement if available
        let approxPerStudentKB = 8.0
        let approxPerItemKB = 4.0
        let totalKB = Double(students.count) * approxPerStudentKB + Double(items.count) * approxPerItemKB
        return totalKB / 1024.0
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

#Preview {
    SettingsView()
}
