import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #82 and #90's restore sheet: a backup, preview or
// restore that failed part-way left the Backups card's progress bar up (and
// its buttons off) until a relaunch; a restore stamped "Last backup just now",
// hiding the "backup is N days old" warning; and Restore Now left the preview
// sheet up, with no progress, over the alert a failure raised.
@Suite("Backups card and restore (Fix1010 J2a)", .serialized)
@MainActor
struct SettingsViewModelFix1010J2aTests {
    private static let lastBackupKey = "LastBackupTimeInterval"

    private struct Harness {
        let model: SettingsViewModel
        let context: NSManagedObjectContext
        let directory: URL
    }

    /// A Backups card over an empty notebook, and a folder for backup files.
    private static func harness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsFix1010J2a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = SettingsViewModel(dependencies: AppDependencies(coreDataStack: stack))
        return Harness(model: model, context: stack.viewContext, directory: directory)
    }

    /// A backup of a notebook holding one child, carrying `preferences`.
    private static func backup(
        in directory: URL, preferences: [String: PreferenceValueDTO] = [:]
    ) async throws -> URL {
        let source = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: source, firstName: "Ada", lastName: "Lovelace")
        #expect(CoreDataTestHelpers.save(source))
        let url = directory.appendingPathComponent("Source").appendingPathExtension(BackupFile.fileExtension)
        let recorder = BackupPipelineRecorder(preferences: PreferencesDTO(values: preferences))
        _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: source, to: url)
        }
        return url
    }

    private static func students(in context: NSManagedObjectContext) -> Int {
        context.safeFetch(CDFetchRequest(CDStudent.self)).count
    }

    /// Runs `body` with this device's last-backup time set to `date`, and
    /// puts the real one back after.
    private static func withLastBackup(_ date: Date?, _ body: () async throws -> Void) async rethrows {
        let saved = UserDefaults.standard.object(forKey: lastBackupKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: lastBackupKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastBackupKey)
            }
        }
        if let date {
            UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: lastBackupKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastBackupKey)
        }
        try await body()
    }

    /// Previews `url` and requires the preview sheet's contents.
    private static func preview(_ url: URL, with harness: Harness) async throws {
        await harness.model.previewImportedURL(viewContext: harness.context, url: url)
        try #require(
            harness.model.restorePreviewData != nil,
            "no preview: \(harness.model.importError ?? "no message")"
        )
    }

    // MARK: - The card after a failure

    @Test("A preview that fails part-way says so and frees the card")
    func failedPreviewFreesTheCard() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        // Looks like a backup (the encrypted archive's first four bytes), isn't one.
        let broken = harness.directory.appendingPathComponent("Broken").appendingPathExtension(BackupFile.fileExtension)
        try (Data("AEA1".utf8) + Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 31) })).write(to: broken)

        await harness.model.previewImportedURL(viewContext: harness.context, url: broken)

        #expect(harness.model.importError != nil)
        #expect(harness.model.restorePreviewData == nil)
        #expect(harness.model.importProgress == 0, "the progress bar would stay up and the buttons off")
        #expect(harness.model.importMessage.isEmpty)
    }

    @Test("A restore that fails part-way says so and frees the card")
    func failedRestoreFreesTheCard() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let url = try await Self.backup(in: harness.directory)
        try await Self.preview(url, with: harness)

        struct Stop: Error {}
        let failing = BackupPipelineRecorder(failure: { $0 == "import Student" ? Stop() : nil })
        harness.model.confirmRestore()
        await BackupPipelineRecorder.$current.withValue(failing) {
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
        }

        #expect(harness.model.importError != nil)
        #expect(harness.model.importProgress == 0, "the progress bar would stay up and the buttons off")
        #expect(Self.students(in: harness.context) == 0)
    }

    // MARK: - The last backup time

    @Test("A restore isn't a backup: the last backup time stays as it was")
    func restoreDoesNotStampTheBackupTime() async throws {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        try await Self.withLastBackup(threeDaysAgo) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            let url = try await Self.backup(in: harness.directory)
            try await Self.preview(url, with: harness)

            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)

            #expect(harness.model.importError == nil)
            #expect(Self.students(in: harness.context) == 1)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == threeDaysAgo.timeIntervalSinceReferenceDate)
        }
    }

    @Test("An older backup's settings don't turn the last backup time back; a fresh device takes the backup's")
    func restoreKeepsTheLaterBackupTime() async throws {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        let carried = [Self.lastBackupKey: PreferenceValueDTO.double(tenDaysAgo.timeIntervalSinceReferenceDate)]

        try await Self.withLastBackup(threeDaysAgo) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory, preferences: carried), with: harness)
            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == threeDaysAgo.timeIntervalSinceReferenceDate)
        }

        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory, preferences: carried), with: harness)
            harness.model.confirmRestore()
            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(harness.model.lastBackupDate?.timeIntervalSinceReferenceDate
                == tenDaysAgo.timeIntervalSinceReferenceDate)
        }
    }

    // MARK: - The preview sheet

    @Test("Restore Now closes the preview first; the restore runs once it has gone, and the card is free after")
    func restoreNowClosesThePreviewFirst() async throws {
        try await Self.withLastBackup(nil) {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.directory) }
            try await Self.preview(try await Self.backup(in: harness.directory), with: harness)

            harness.model.confirmRestore()
            #expect(harness.model.restorePreviewData == nil, "the sheet closes on Restore Now")
            #expect(Self.students(in: harness.context) == 0, "nothing restored while the sheet is still going")

            await harness.model.restorePreviewDismissed(viewContext: harness.context)
            #expect(Self.students(in: harness.context) == 1)
            #expect(harness.model.importError == nil)
            #expect(harness.model.importProgress == 0)
            #expect(harness.model.operationSummary != nil)
        }
    }

    @Test("Closing the preview any other way restores nothing, then or later")
    func dismissingWithoutRestoreNowRestoresNothing() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        try await Self.preview(try await Self.backup(in: harness.directory), with: harness)

        harness.model.restorePreviewData = nil  // Cancel, or a swipe down
        await harness.model.restorePreviewDismissed(viewContext: harness.context)
        await harness.model.performImportConfirmed(viewContext: harness.context)

        #expect(Self.students(in: harness.context) == 0)
        #expect(harness.model.operationSummary == nil)
    }
}
