import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Settings Transfer

/// Sync and backup › Move settings to another device: export the settings to a
/// file, or import one written on another device.
struct SettingsTransferView: View {
    @State private var showingImporter = false
    @State private var resultMessage: String?

    var body: some View {
        SettingsGroup(
            .settingsTransfer,
            footer: "Saves your settings as a file to import on another device: the school year, messages, " +
                "look and feel, Intelligence, backup choices and how your screens are arranged. Students, " +
                "lessons and other records aren't included; iCloud and backups carry those."
        ) {
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    exportSettingsToFile()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    showingImporter = true
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let url = try result.get().first {
                    // A file from Files or iCloud Drive is outside the sandbox.
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try SettingsExportService.importSettings(from: data)
                    resultMessage = "Settings imported."
                }
            } catch let error as SettingsExportService.SettingsImportError {
                resultMessage = error.errorDescription
            } catch {
                resultMessage = AppErrorMessages.importMessage(for: error, fileType: "settings file")
            }
        }
        .alert("Settings", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let resultMessage {
                Text(resultMessage)
            }
        }
    }

    private func exportSettingsToFile() {
        guard let data = SettingsExportService.exportSettings() else {
            resultMessage = "Couldn't prepare your settings for export."
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmic-daybook-settings.json")
        do {
            try data.write(to: tempURL)
        } catch {
            resultMessage = AppErrorMessages.userMessage(for: error, context: "exporting settings")
            return
        }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([tempURL])
        #else
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }
        rootVC.present(activityVC, animated: true)
        #endif
    }
}
