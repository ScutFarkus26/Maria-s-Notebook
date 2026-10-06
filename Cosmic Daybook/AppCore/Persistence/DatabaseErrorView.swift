import SwiftUI
import OSLog
import UniformTypeIdentifiers
#if !os(macOS)
import UIKit
#endif

/// Full-screen error view shown when database initialization fails.
/// Provides recovery actions: Re-download, Restore, Export Diagnostics.
struct DatabaseErrorView: View {
    @Bindable var errorCoordinator: DatabaseErrorCoordinator
    @Bindable var appRouter: AppRouter

    @State private var resetError: String?
    @State private var showingExportSheet = false
    @State private var showResetConfirmation = false

    // Restore from a Backup… (`FreshNotebookRestore`)
    @State private var showingBackupPicker = false
    @State private var chosenBackup: URL?
    @State private var showRestoreConfirmation = false
    @State private var restoreStep: (fraction: Double, message: String)?
    @State private var restoreError: String?
    @State private var restoredMessage: String?
    @State private var showRestored = false

    private static let logger = Logger.database

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Open Your Notebook", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.destructive)
        } description: {
            VStack(spacing: 12) {
                Text(errorCoordinator.userMessage)
                    .multilineTextAlignment(.center)

                // The raw error is for a bug report, not the message.
                if errorCoordinator.error != nil {
                    TechnicalDetailsDisclosure(details: technicalDetails)
                        .frame(maxWidth: 500)
                }
            }
            .padding()
        } actions: {
            VStack(spacing: 16) {
                // The same recovery as Troubleshooting's "Re-download from iCloud…"
                switch errorCoordinator.redownloadOffer {
                case .button:
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Re-download from iCloud…", systemImage: "icloud.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    // It quits the app, which would cut a restore off half done.
                    .disabled(errorCoordinator.isRestoringBackup)
                case .unavailable(let reason):
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                case .hidden:
                    EmptyView()
                }

                if let resetError {
                    Text(resetError)
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                }

                restoreSection

                // Export Diagnostics
                #if os(macOS)
                Button {
                    exportDiagnostics()
                } label: {
                    Label("Export Diagnostics", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                #else
                ShareLink(item: errorCoordinator.exportDiagnostics()) {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding()
            .frame(maxWidth: 500)
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $showingExportSheet,
            document: DiagnosticsDocument(content: errorCoordinator.exportDiagnostics()),
            contentType: .plainText,
            defaultFilename: "database-error-diagnostics.txt"
        ) { result in
            if case .success = result {
                Logger.database.info("Diagnostics exported successfully")
            }
        }
        #endif
        .alert("Restore This Backup?", isPresented: $showRestoreConfirmation, presenting: chosenBackup) { url in
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                Task { await restoreBackup(from: url) }
            }
        } message: { _ in
            Text(
                "The backup becomes your notebook on this device. The notebook that wouldn't open is set "
                + "aside on this device, not deleted; anything added since the backup was made stays only "
                + "there. When it's done, close the app and open it again to use your notebook."
            )
        }
        .alert("Your Backup Is Restored", isPresented: $showRestored) {
            Button("Close Cosmic Daybook") {
                quitApp()
            }
        } message: {
            Text(restoredMessage ?? "")
        }
        .alert("Re-download from iCloud?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-download", role: .destructive) {
                armRedownloadAndQuit()
            }
        } message: {
            Text(
                "This removes your notebook from this device only. Your notebook in iCloud stays safe "
                + "and downloads again when you reopen the app. Changes that hadn't reached iCloud yet "
                + "are lost. The app closes now; open it again to start the download."
            )
        }
    }

    /// Arms the reset for the next launch and quits: the stores are thrown
    /// away before anything opens them, never under the running app.
    private func armRedownloadAndQuit() {
        resetError = nil
        guard errorCoordinator.armRedownload() else {
            resetError = DatabaseErrorCoordinator.redownloadNeedsSyncMessage
            return
        }
        quitApp()
    }

    /// Restore from a Backup…: the button while iCloud sync is off, what to
    /// do instead while it's on, nothing where a restore can't help
    /// (`DatabaseErrorCoordinator.restoreOffer`).
    @ViewBuilder
    private var restoreSection: some View {
        switch errorCoordinator.restoreOffer {
        case .button:
            Divider()
                .padding(.vertical, 8)
            if let restoreStep {
                ProgressView(value: restoreStep.fraction) {
                    Text(restoreStep.message)
                        .font(.callout)
                }
            } else {
                Button {
                    restoreError = nil
                    showingBackupPicker = true
                } label: {
                    Label("Restore from a Backup\u{2026}", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(errorCoordinator.isRestoringBackup)
                // On the button, so the screen's own view keeps just one
                // file panel (the Mac's diagnostics exporter).
                .fileImporter(
                    isPresented: $showingBackupPicker,
                    allowedContentTypes: Self.backupContentTypes,
                    onCompletion: backupPicked
                )
            }
            if let restoreError {
                Text(restoreError)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
                    .multilineTextAlignment(.center)
            }
        case .guidance(let text):
            Divider()
                .padding(.vertical, 8)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .hidden:
            EmptyView()
        }
    }

    /// The backup files the picker offers: the app's own type, its file
    /// extension, and any file, for when the system doesn't know the type.
    private static let backupContentTypes: [UTType] = [
        UTType(exportedAs: "com.cosmic-daybook.backup"),
        UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
        .data
    ]

    private func backupPicked(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            chosenBackup = url
            showRestoreConfirmation = true
        case .failure(let error):
            Self.logger.warning("Backup file picker failed: \(error, privacy: .public)")
            restoreError = "Couldn't open the backup file you chose. Choose it again and try once more."
        }
    }

    /// Restores `url` in place of the notebook that wouldn't open, then says
    /// so; the guide closes the app from there.
    private func restoreBackup(from url: URL) async {
        restoreError = nil
        restoreStep = (0, "Starting\u{2026}")
        defer { restoreStep = nil }
        do {
            let result = try await errorCoordinator.restoreBackupIntoFreshNotebook(
                from: url, appRouter: appRouter
            ) { fraction, message in
                restoreStep = (fraction, message)
            }
            restoredMessage = DatabaseErrorCoordinator.restoredMessage(warnings: result.summary.warnings)
            showRestored = true
        } catch {
            Self.logger.error("Restore from the error screen failed: \(String(describing: error), privacy: .public)")
            restoreError = DatabaseErrorCoordinator.restoreFailureMessage(for: error)
        }
    }

    /// Closes the app; the next launch opens the stores afresh.
    private func quitApp() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #else
        exit(0)
        #endif
    }

    /// What the launch recorded about the error: the store's facts or the
    /// system's text, with its domain and code.
    private var technicalDetails: String {
        guard let error = errorCoordinator.error else { return "" }
        let details = errorCoordinator.errorDetails
        return details.isEmpty ? DatabaseErrorCoordinator.technicalDescription(of: error) : details
    }

    #if os(macOS)
    private func exportDiagnostics() {
        showingExportSheet = true
    }
    #endif
}

#if os(macOS)
/// CDDocument wrapper for diagnostics export
private struct DiagnosticsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        content = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
#endif
