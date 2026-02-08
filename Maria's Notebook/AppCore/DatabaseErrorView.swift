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
    @ObservedObject var errorCoordinator: DatabaseErrorCoordinator
    @ObservedObject var appRouter: AppRouter
    
    @State private var isResetting = false
    @State private var resetError: String?
    @State private var showingExportSheet = false
    @State private var showResetConfirmation = false
    
    var body: some View {
        ContentUnavailableView {
            Label("Database Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } description: {
            VStack(spacing: 12) {
                Text("The app could not initialize the database.")
                    .multilineTextAlignment(.center)
                
                if let error = errorCoordinator.error {
                    VStack(spacing: 8) {
                        Text("Error Details:")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ScrollView {
                            Text(error.localizedDescription)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            .padding()
        } actions: {
            VStack(spacing: 16) {
                // Reset Local Database
                Button {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Local Database", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResetting)
                
                if isResetting {
                    ProgressView()
                        .controlSize(.small)
                }
                
                if let resetError = resetError {
                    Text(resetError)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                if #available(iOS 16.0, *) {
                    ShareLink(item: errorCoordinator.exportDiagnostics()) {
                        Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        // Fallback for older iOS versions
                        let pasteboard = UIPasteboard.general
                        pasteboard.string = errorCoordinator.exportDiagnostics()
                    } label: {
                        Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
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
        .alert("Reset Local Database?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                resetLocalDatabase()
            }
        } message: {
            Text("This deletes local data on this device. CloudKit data is preserved and will re-sync after restart. The app will restart automatically.")
        }
    }
    
    private func resetLocalDatabase() {
        isResetting = true
        resetError = nil
        
        Task { @MainActor in
            do {
                try errorCoordinator.resetLocalDatabase()
                // After reset, restart the app
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #else
                exit(0)
                #endif
            } catch {
                resetError = "Failed to reset database: \(error.localizedDescription)"
                isResetting = false
                Logger.database.error("Failed to reset database: \(error)")
            }
        }
    }
    
    #if os(macOS)
    private func exportDiagnostics() {
        showingExportSheet = true
    }
    #endif
}

#if os(macOS)
/// Document wrapper for diagnostics export
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

