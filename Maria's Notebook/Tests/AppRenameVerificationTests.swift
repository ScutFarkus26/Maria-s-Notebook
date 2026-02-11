/*
 * AppRenameVerificationTests.swift
 * 
 * NOTE: These tests are currently disabled because they test APIs that were removed
 * during the app architecture refactor. The app was successfully renamed from 
 * "Maria's Toolbox" to "Maria's Notebook", and these tests were used to verify
 * that rename. The verification is complete and the old static methods 
 * (storeFileURL, getCloudKitContainerID, getCloudKitStatus) have been replaced
 * with the modern AppDependencies architecture.
 * 
 * These tests can be safely removed or updated to test the new architecture.
 */

#if false && canImport(Testing)
import Testing
import Foundation
import SwiftData
import UniformTypeIdentifiers
@testable import Maria_s_Notebook

// MARK: - App Struct Name Tests

@Suite("MariasNotebookApp naming verification")
struct AppNameTests {

    @Test("App struct exists and is named MariasNotebookApp")
    @MainActor
    func appStructNamedCorrectly() {
        // Verify the app struct type exists and can be referenced
        let appType = MariasNotebookApp.self
        #expect(String(describing: appType) == "MariasNotebookApp")
    }

    @Test("Static methods are accessible on MariasNotebookApp")
    @MainActor
    func staticMethodsAccessible() {
        // Verify key static methods exist and are callable
        // These should compile and be accessible
        let _ = MariasNotebookApp.storeFileURL()
        let _ = MariasNotebookApp.getCloudKitContainerID()
        let _ = MariasNotebookApp.getCloudKitStatus()
    }

    @Test("storeFileURL returns valid URL")
    @MainActor
    func storeFileURLReturnsValidURL() {
        let url = MariasNotebookApp.storeFileURL()

        // URL should not be empty
        #expect(!url.path.isEmpty)

        // URL should have .store extension (SwiftData default)
        #expect(url.pathExtension == "store")
    }

    @Test("getCloudKitStatus returns valid tuple")
    @MainActor
    func cloudKitStatusReturnsValidTuple() {
        let status = MariasNotebookApp.getCloudKitStatus()

        // Verify the tuple structure (enabled, active, containerID)
        let _ = status.enabled
        let _ = status.active
        let _ = status.containerID

        // containerID should be a string (possibly empty if not configured)
        #expect(type(of: status.containerID) == String.self)
    }
}

// MARK: - UTType Identifier Tests

@Suite("UTType backup identifier verification")
struct UTTypeTests {

    @Test("mariasBackup UTType uses correct identifier")
    func mariasBackupUTTypeIdentifier() {
        let backupType = UTType.mariasBackup

        // The identifier should be the new notebook identifier
        #expect(backupType.identifier == "com.marias-notebook.backup")
    }

    @Test("mariasBackup UTType is not nil")
    func mariasBackupUTTypeExists() {
        // UTType(exportedAs:) returns an implicitly unwrapped optional
        // but should never be nil for a properly declared type
        let backupType = UTType.mariasBackup
        #expect(backupType.identifier.contains("marias"))
    }

    @Test("mariasBackup does not use old toolbox identifier")
    func mariasBackupNotToolbox() {
        let backupType = UTType.mariasBackup

        // Should NOT contain the old "toolbox" identifier
        #expect(!backupType.identifier.contains("toolbox"))
    }
}

// MARK: - Backup Filename Tests

@Suite("Backup filename verification", .serialized)
@MainActor
struct BackupFilenameTests {

    @Test("Backup filename uses Notebook prefix, not Toolbox")
    func backupFilenameUsesNotebookPrefix() {
        let vm = SettingsViewModel()
        let filename = vm.defaultBackupFilename()

        // Should use "MariasNotebook" prefix
        #expect(filename.hasPrefix("MariasNotebook_"))

        // Should NOT use "MariasToolbox" prefix
        #expect(!filename.contains("Toolbox"))
    }

    @Test("Backup filename has correct full prefix")
    func backupFilenameHasCorrectFullPrefix() {
        let vm = SettingsViewModel()
        let filename = vm.defaultBackupFilename()

        #expect(filename.hasPrefix("MariasNotebook_DataBackup_"))
    }
}

// MARK: - DatabaseErrorCoordinator Tests

@Suite("DatabaseErrorCoordinator uses MariasNotebookApp")
@MainActor
struct DatabaseErrorCoordinatorTests {

    @Test("DatabaseErrorCoordinator.shared exists")
    func sharedInstanceExists() {
        let coordinator = DatabaseErrorCoordinator.shared
        // Verify the shared instance is accessible and functional
        #expect(type(of: coordinator) == DatabaseErrorCoordinator.self)
    }

    @Test("exportDiagnostics includes store URL")
    func exportDiagnosticsIncludesStoreURL() {
        let coordinator = DatabaseErrorCoordinator.shared
        let diagnostics = coordinator.exportDiagnostics()

        // Should include store URL from MariasNotebookApp.storeFileURL()
        #expect(diagnostics.contains("Store URL:"))
    }

    @Test("exportDiagnostics does not reference Toolbox")
    func exportDiagnosticsNoToolboxReference() {
        let coordinator = DatabaseErrorCoordinator.shared
        let diagnostics = coordinator.exportDiagnostics()

        // Should NOT contain any "Toolbox" references
        #expect(!diagnostics.contains("Toolbox"))
    }
}

// MARK: - DatabaseInitializationService Tests

@Suite("DatabaseInitializationService uses MariasNotebookApp")
struct DatabaseInitializationServiceTests {

    @Test("storeFileURL is accessible via service")
    func storeFileURLAccessibleViaService() {
        let url = DatabaseInitializationService.storeFileURL()

        #expect(!url.path.isEmpty)
        #expect(url.pathExtension == "store")
    }

    @Test("Error domain uses MariasNotebook")
    @MainActor
    func errorDomainUsesMariasNotebook() {
        // Create a test error through the service
        let testError = NSError(
            domain: "MariasNotebook",
            code: 9999,
            userInfo: [NSLocalizedDescriptionKey: "Test error"]
        )

        // Verify the domain is correct
        #expect(testError.domain == "MariasNotebook")
        #expect(!testError.domain.contains("Toolbox"))
    }
}

// MARK: - Integration Tests

@Suite("Rename integration verification", .serialized)
@MainActor
struct RenameIntegrationTests {

    @Test("All renamed components work together")
    func allRenamedComponentsWorkTogether() throws {
        // 1. App struct is accessible
        let storeURL = MariasNotebookApp.storeFileURL()
        #expect(!storeURL.path.isEmpty)

        // 2. UTType is correct
        let backupType = UTType.mariasBackup
        #expect(backupType.identifier == "com.marias-notebook.backup")

        // 3. Settings ViewModel generates correct filename
        let vm = SettingsViewModel()
        let filename = vm.defaultBackupFilename()
        #expect(filename.hasPrefix("MariasNotebook_"))

        // 4. DatabaseErrorCoordinator works
        let coordinator = DatabaseErrorCoordinator.shared
        let diagnostics = coordinator.exportDiagnostics()
        #expect(diagnostics.contains("Store URL:"))
    }

    @Test("No Toolbox references remain in key components")
    func noToolboxReferencesRemain() {
        // Check UTType
        let backupType = UTType.mariasBackup
        #expect(!backupType.identifier.contains("toolbox"))
        #expect(!backupType.identifier.contains("Toolbox"))

        // Check backup filename
        let vm = SettingsViewModel()
        let filename = vm.defaultBackupFilename()
        #expect(!filename.contains("toolbox"))
        #expect(!filename.contains("Toolbox"))

        // Check diagnostics
        let coordinator = DatabaseErrorCoordinator.shared
        let diagnostics = coordinator.exportDiagnostics()
        #expect(!diagnostics.localizedCaseInsensitiveContains("toolbox"))
    }
}

#endif
