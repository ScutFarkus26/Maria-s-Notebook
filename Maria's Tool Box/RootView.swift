import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case lessons = "Lessons"
        case students = "Students"
        case planning = "Planning"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .lessons

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .frame(minHeight: 30)
                                .background(pillBackground(for: tab))
                                .foregroundStyle(pillForeground(for: tab))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Active view
            Group {
                switch selectedTab {
                case .lessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
                case .settings:
                    SettingsRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Styling

    private func pillBackground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
        }
    }

    private func pillForeground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }
}

// MARK: - Root views for each tab

struct LessonsRootView: View {
    var body: some View {
        Text("Lessons View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StudentsRootView: View {
    var body: some View {
        StudentsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlanningRootView: View {
    var body: some View {
        Text("Planning View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsRootView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isShowingAlert: Bool = false
    @State private var isConfirmingRestore: Bool = false
    @State private var pendingRestoreURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold, design: .rounded))

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
                showAlert(title: "Backup Exported", message: "Saved to \(url.lastPathComponent)")
            }
#else
            // TODO: iOS export flow if needed
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
}

#Preview {
    RootView()
}
