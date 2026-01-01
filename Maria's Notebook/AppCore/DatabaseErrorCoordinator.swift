import Foundation
import SwiftUI
import Combine

/// Coordinates database initialization errors and recovery actions.
/// Provides app-wide error state management for database failures.
@MainActor
final class DatabaseErrorCoordinator: ObservableObject {
    static let shared = DatabaseErrorCoordinator()
    
    @Published var error: Error?
    @Published var errorDetails: String = ""
    
    private init() {}
    
    /// Sets a database initialization error
    func setError(_ error: Error, details: String = "") {
        self.error = error
        self.errorDetails = details.isEmpty ? error.localizedDescription : details
        
        // Log the error
        print("🔴 DatabaseErrorCoordinator: Database initialization error set")
        print("🔴 Error: \(error.localizedDescription)")
        if !details.isEmpty {
            print("🔴 Details: \(details)")
        }
        if let nsError = error as NSError? {
            print("🔴 Domain: \(nsError.domain), Code: \(nsError.code)")
            print("🔴 UserInfo: \(nsError.userInfo)")
        }
    }
    
    /// Clears the error state
    func clearError() {
        self.error = nil
        self.errorDetails = ""
        print("✅ DatabaseErrorCoordinator: Error state cleared")
    }
    
    /// Resets the local database by deleting the store file
    /// This only deletes local data on this device and does NOT delete CloudKit data.
    func resetLocalDatabase() throws {
        // Delete the persistent store (includes logging)
        try MariasToolboxApp.resetPersistentStore()
        
        // Clear error state
        clearError()
        MariasToolboxApp.initError = nil
        
        // Clear error flags
        UserDefaults.standard.removeObject(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey)
        UserDefaults.standard.set(false, forKey: MariasToolboxApp.ephemeralSessionFlagKey)
        
        print("✅ DatabaseErrorCoordinator: Local database reset successfully. CloudKit data preserved.")
    }
    
    /// Exports diagnostic information about the error
    func exportDiagnostics() -> String {
        var diagnostics: [String] = []
        
        diagnostics.append("=== Database Error Diagnostics ===")
        diagnostics.append("")
        diagnostics.append("Timestamp: \(Date().formatted())")
        diagnostics.append("")
        
        // Error information
        if let error = error {
            diagnostics.append("Error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                diagnostics.append("Domain: \(nsError.domain)")
                diagnostics.append("Code: \(nsError.code)")
                if !nsError.userInfo.isEmpty {
                    diagnostics.append("UserInfo: \(nsError.userInfo)")
                }
            }
        } else {
            diagnostics.append("Error: No error information available")
        }
        
        if !errorDetails.isEmpty {
            diagnostics.append("")
            diagnostics.append("Details: \(errorDetails)")
        }
        
        diagnostics.append("")
        diagnostics.append("=== Environment Information ===")
        diagnostics.append("")
        
        // System information
        #if os(macOS)
        diagnostics.append("Platform: macOS")
        diagnostics.append("Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #elseif os(iOS)
        diagnostics.append("Platform: iOS")
        diagnostics.append("Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #else
        diagnostics.append("Platform: Unknown")
        #endif
        
        // App information
        if let bundleID = Bundle.main.bundleIdentifier {
            diagnostics.append("Bundle ID: \(bundleID)")
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            diagnostics.append("App Version: \(version)")
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            diagnostics.append("Build: \(build)")
        }
        
        diagnostics.append("")
        diagnostics.append("=== Database Configuration ===")
        diagnostics.append("")
        
        // Store URL
        let storeURL = MariasToolboxApp.storeFileURL()
        diagnostics.append("Store URL: \(storeURL.path)")
        let fileManager = FileManager.default
        diagnostics.append("Store exists: \(fileManager.fileExists(atPath: storeURL.path))")
        if fileManager.fileExists(atPath: storeURL.path) {
            diagnostics.append("Store readable: \(fileManager.isReadableFile(atPath: storeURL.path))")
            diagnostics.append("Store writable: \(fileManager.isWritableFile(atPath: storeURL.path))")
            
            // File size
            if let attrs = try? fileManager.attributesOfItem(atPath: storeURL.path),
               let size = attrs[.size] as? Int64 {
                diagnostics.append("Store size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            }
        }
        
        // UserDefaults flags
        diagnostics.append("")
        diagnostics.append("=== UserDefaults Flags ===")
        diagnostics.append("")
        diagnostics.append("Ephemeral Session: \(UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey))")
        diagnostics.append("CloudKit Enabled: \(UserDefaults.standard.bool(forKey: MariasToolboxApp.enableCloudKitKey))")
        diagnostics.append("CloudKit Active: \(UserDefaults.standard.bool(forKey: MariasToolboxApp.cloudKitActiveKey))")
        
        if let lastError = UserDefaults.standard.string(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey) {
            diagnostics.append("Last Error: \(lastError)")
        }
        
        return diagnostics.joined(separator: "\n")
    }
}
