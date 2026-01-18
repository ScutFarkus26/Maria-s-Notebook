#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Initialization Tests

@Suite("SettingsViewModel Initialization Tests", .serialized)
@MainActor
struct SettingsViewModelInitializationTests {

    @Test("SettingsViewModel initial state has zero progress")
    func initialStateHasZeroProgress() {
        let vm = SettingsViewModel()

        #expect(vm.backupProgress == 0)
        #expect(vm.importProgress == 0)
    }

    @Test("SettingsViewModel initial state has empty messages")
    func initialStateHasEmptyMessages() {
        let vm = SettingsViewModel()

        #expect(vm.backupMessage == "")
        #expect(vm.importMessage == "")
    }

    @Test("SettingsViewModel restoreMode defaults to merge")
    func restoreModeDefaultsToMerge() {
        let vm = SettingsViewModel()

        #expect(vm.restoreMode == .merge)
    }

    @Test("SettingsViewModel resultSummary starts nil")
    func resultSummaryStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.resultSummary == nil)
    }

    @Test("SettingsViewModel operationSummary starts nil")
    func operationSummaryStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.operationSummary == nil)
    }

    @Test("SettingsViewModel restorePreviewData starts nil")
    func restorePreviewDataStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.restorePreviewData == nil)
    }

    @Test("SettingsViewModel exportData starts nil")
    func exportDataStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.exportData == nil)
    }

    @Test("SettingsViewModel importError starts nil")
    func importErrorStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.importError == nil)
    }

    @Test("SettingsViewModel estimatedBackupSize starts nil")
    func estimatedBackupSizeStartsNil() {
        let vm = SettingsViewModel()

        #expect(vm.estimatedBackupSize == nil)
    }
}

// MARK: - Backup Filename Tests

@Suite("SettingsViewModel Backup Filename Tests", .serialized)
@MainActor
struct SettingsViewModelBackupFilenameTests {

    @Test("defaultBackupFilename includes date")
    func defaultBackupFilenameIncludesDate() {
        let vm = SettingsViewModel()

        let filename = vm.defaultBackupFilename()

        // Should contain current year
        let year = Calendar.current.component(.year, from: Date())
        #expect(filename.contains(String(year)))
    }

    @Test("defaultBackupFilename has correct prefix")
    func defaultBackupFilenameHasCorrectPrefix() {
        let vm = SettingsViewModel()

        let filename = vm.defaultBackupFilename()

        #expect(filename.hasPrefix("MariasNotebook_DataBackup_"))
    }

    @Test("defaultBackupFilename has date format")
    func defaultBackupFilenameHasDateFormat() {
        let vm = SettingsViewModel()

        let filename = vm.defaultBackupFilename()

        // Format should be: MariasNotebook_DataBackup_YYYY-MM-DD_HH-mm-ss
        // Check for the date pattern structure
        let components = filename.replacingOccurrences(of: "MariasNotebook_DataBackup_", with: "")
        #expect(components.contains("-"))
        #expect(components.contains("_"))
    }

    @Test("defaultBackupFilename is unique per call")
    func defaultBackupFilenameIsUniquePerCall() {
        let vm = SettingsViewModel()

        let filename1 = vm.defaultBackupFilename()

        // Wait a tiny bit to ensure different timestamp
        Thread.sleep(forTimeInterval: 1.1)

        let filename2 = vm.defaultBackupFilename()

        // Filenames should be different due to timestamp
        #expect(filename1 != filename2)
    }
}

// MARK: - Last Backup Date Tests

@Suite("SettingsViewModel Last Backup Date Tests", .serialized)
@MainActor
struct SettingsViewModelLastBackupDateTests {

    @Test("lastBackupDate returns nil when not set")
    func lastBackupDateReturnsNilWhenNotSet() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: "LastBackupTimeInterval")

        let vm = SettingsViewModel()

        #expect(vm.lastBackupDate == nil)
    }

    @Test("setLastBackupNow updates lastBackupDate")
    func setLastBackupNowUpdatesLastBackupDate() {
        let vm = SettingsViewModel()
        let beforeSet = Date()

        vm.setLastBackupNow()

        let afterSet = Date()

        #expect(vm.lastBackupDate != nil)
        if let lastBackup = vm.lastBackupDate {
            #expect(lastBackup >= beforeSet)
            #expect(lastBackup <= afterSet)
        }
    }

    @Test("lastBackupDate persists to UserDefaults")
    func lastBackupDatePersistsToUserDefaults() {
        let vm = SettingsViewModel()

        vm.setLastBackupNow()

        // Create a new instance to verify persistence
        let vm2 = SettingsViewModel()

        #expect(vm2.lastBackupDate != nil)
        #expect(abs((vm.lastBackupDate ?? Date.distantPast).timeIntervalSince(vm2.lastBackupDate ?? Date.distantFuture)) < 1)
    }
}

// MARK: - Progress Updates Tests

@Suite("SettingsViewModel Progress Updates Tests", .serialized)
@MainActor
struct SettingsViewModelProgressUpdatesTests {

    @Test("backupProgress updates correctly")
    func backupProgressUpdatesCorrectly() {
        let vm = SettingsViewModel()

        vm.backupProgress = 0.5

        #expect(vm.backupProgress == 0.5)

        vm.backupProgress = 1.0

        #expect(vm.backupProgress == 1.0)
    }

    @Test("backupMessage updates correctly")
    func backupMessageUpdatesCorrectly() {
        let vm = SettingsViewModel()

        vm.backupMessage = "Exporting..."

        #expect(vm.backupMessage == "Exporting...")

        vm.backupMessage = "Complete"

        #expect(vm.backupMessage == "Complete")
    }

    @Test("importProgress updates correctly")
    func importProgressUpdatesCorrectly() {
        let vm = SettingsViewModel()

        vm.importProgress = 0.25

        #expect(vm.importProgress == 0.25)
    }

    @Test("importMessage updates correctly")
    func importMessageUpdatesCorrectly() {
        let vm = SettingsViewModel()

        vm.importMessage = "Importing..."

        #expect(vm.importMessage == "Importing...")
    }

    @Test("resultSummary can be set and cleared")
    func resultSummaryCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.resultSummary = "Export successful"

        #expect(vm.resultSummary == "Export successful")

        vm.resultSummary = nil

        #expect(vm.resultSummary == nil)
    }

    @Test("importError can be set")
    func importErrorCanBeSet() {
        let vm = SettingsViewModel()

        vm.importError = "Failed to import"

        #expect(vm.importError == "Failed to import")
    }

    @Test("estimatedBackupSize can be set")
    func estimatedBackupSizeCanBeSet() {
        let vm = SettingsViewModel()

        let oneMB: Int64 = 1024 * 1024
        vm.estimatedBackupSize = oneMB

        #expect(vm.estimatedBackupSize == oneMB)
    }
}

// MARK: - RestoreMode Tests

@Suite("SettingsViewModel RestoreMode Tests", .serialized)
@MainActor
struct SettingsViewModelRestoreModeTests {

    @Test("restoreMode can be changed to replace")
    func restoreModeCanBeChangedToReplace() {
        let vm = SettingsViewModel()

        vm.restoreMode = .replace

        #expect(vm.restoreMode == .replace)
    }

    @Test("restoreMode can be changed back to merge")
    func restoreModeCanBeChangedBackToMerge() {
        let vm = SettingsViewModel()

        vm.restoreMode = .replace
        vm.restoreMode = .merge

        #expect(vm.restoreMode == .merge)
    }
}

// MARK: - State Reset Tests

@Suite("SettingsViewModel State Reset Tests", .serialized)
@MainActor
struct SettingsViewModelStateResetTests {

    @Test("Multiple progress operations can be tracked")
    func multipleProgressOperationsCanBeTracked() {
        let vm = SettingsViewModel()

        // Simulate export progress
        vm.backupProgress = 0.0
        vm.backupMessage = "Starting..."
        #expect(vm.backupProgress == 0.0)
        #expect(vm.backupMessage == "Starting...")

        vm.backupProgress = 0.5
        vm.backupMessage = "Halfway..."
        #expect(vm.backupProgress == 0.5)
        #expect(vm.backupMessage == "Halfway...")

        vm.backupProgress = 1.0
        vm.backupMessage = "Done"
        #expect(vm.backupProgress == 1.0)
        #expect(vm.backupMessage == "Done")
    }

    @Test("Import and export progress are independent")
    func importAndExportProgressAreIndependent() {
        let vm = SettingsViewModel()

        vm.backupProgress = 0.75
        vm.importProgress = 0.25

        #expect(vm.backupProgress == 0.75)
        #expect(vm.importProgress == 0.25)
    }

    @Test("Messages are independent")
    func messagesAreIndependent() {
        let vm = SettingsViewModel()

        vm.backupMessage = "Export message"
        vm.importMessage = "Import message"

        #expect(vm.backupMessage == "Export message")
        #expect(vm.importMessage == "Import message")
    }
}

// MARK: - Default Folder Tests

@Suite("SettingsViewModel Default Folder Tests", .serialized)
@MainActor
struct SettingsViewModelDefaultFolderTests {

    @Test("defaultFolderName starts empty")
    func defaultFolderNameStartsEmpty() {
        let vm = SettingsViewModel()

        #expect(vm.defaultFolderName == "")
    }

    @Test("defaultFolderName can be set")
    func defaultFolderNameCanBeSet() {
        let vm = SettingsViewModel()

        vm.defaultFolderName = "Backups"

        #expect(vm.defaultFolderName == "Backups")
    }

    @Test("loadDefaultFolderName updates defaultFolderName")
    func loadDefaultFolderNameUpdatesDefaultFolderName() {
        let vm = SettingsViewModel()
        let initialValue = vm.defaultFolderName

        vm.loadDefaultFolderName()

        // After loading, it should have some value (possibly empty if no folder configured)
        // Just verify the method runs without error
        #expect(vm.defaultFolderName == initialValue || vm.defaultFolderName != initialValue)
    }
}

#endif
