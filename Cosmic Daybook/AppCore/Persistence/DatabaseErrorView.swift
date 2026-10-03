import SwiftUI
import OSLog
#if os(macOS)
import UniformTypeIdentifiers
#else
import UIKit
#endif

/// Full-screen error view shown when database initialization fails.
/// Provides recovery actions: Reset, Restore, Export Diagnostics.
struct DatabaseErrorView: View {
    @Bindable var errorCoordinator: DatabaseErrorCoordinator
    @Bindable var appRouter: AppRouter
    
    @State private var isResetting = false
    @State private var resetError: String?
    @State private var showingExportSheet = false
    @State private var showResetConfirmation = false
    
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
                Button {
                    showResetConfirmation = true
                } label: {
                    Label("Re-download from iCloud…", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResetting)
                
                if isResetting {
                    ProgressView()
                        .controlSize(.small)
                }
                
                if let resetError {
                    Text(resetError)
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Restore Backup
                Button {
                    appRouter.requestRestoreBackup()
                } label: {
                    Label("Restore Backup", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                
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
        .alert("Re-download from iCloud?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-download", role: .destructive) {
                resetLocalDatabase()
            }
        } message: {
            Text(
                "This removes your notebook from this device only. Your notebook in iCloud stays safe "
                + "and downloads again when you reopen the app. Changes that hadn't reached iCloud yet "
                + "are lost. The app closes once it's done."
            )
        }
    }
    
    private func resetLocalDatabase() {
        isResetting = true
        resetError = nil
        
        Task {
            do {
                try errorCoordinator.resetLocalDatabase()
                // After reset, restart the app
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #else
                exit(0)
                #endif
            } catch {
                resetError = "Couldn't clear this device's copy. Quit and reopen the app, then try again."
                isResetting = false
                Logger.database.error("Failed to reset database: \(error)")
            }
        }
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
