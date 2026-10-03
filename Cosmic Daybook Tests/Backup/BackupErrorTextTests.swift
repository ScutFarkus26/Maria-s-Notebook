import Foundation
import Testing
@testable import CosmicDaybook

/// The backup and restore errors are what the Backups card's alert and the Overview's
/// backup row say (`AppErrorMessages.backupMessage` lets an app-defined error speak for
/// itself), so each says what happened and what to do, and never carries the file's
/// path, a Keychain status, a type name or the underlying error's text: those go to the
/// log, through the error's own `String(describing:)`.
@Suite("Backup error text")
@MainActor
struct BackupErrorTextTests {
    private struct Boom: LocalizedError {
        var errorDescription: String? { "NSCocoaErrorDomain 134030 raw Core Data text" }
    }

    private static let path = URL(fileURLWithPath: "/Users/someone/Developer/Repo/Backups/Daybook.mtbbackup")

    /// The raw values the errors below are built with; none may reach the text.
    private static let raw = [
        "/Users", "Developer", "Repo", "Daybook.mtbbackup", "-25300", "StudentEntity", "Boom",
        "134030", "NSCocoa", "manifest did not round-trip", "photo-17.heic", "PAT(string)", "ndjson", "v17", "36"
    ]

    private func expectPlain(_ error: Error, sourceLocation: SourceLocation = #_sourceLocation) {
        let text = (error as? LocalizedError)?.errorDescription
        #expect(text?.isEmpty == false, "\(error) has no text", sourceLocation: sourceLocation)
        let message = text ?? ""
        for marker in Self.raw {
            #expect(!message.contains(marker), "\"\(message)\" carries \(marker)", sourceLocation: sourceLocation)
        }
        // And the alert shows that same text.
        #expect(AppErrorMessages.backupMessage(for: error, operation: "restore your backup") == message,
                sourceLocation: sourceLocation)
    }

    @Test("Archive, reader, writer and Keychain errors carry no path, status or type name")
    func archiveErrorsArePlain() {
        let errors: [Error] = [
            BackupArchive.ArchiveError.cannotOpenFileForWrite(Self.path),
            BackupArchive.ArchiveError.cannotOpenFileForRead(Self.path),
            BackupArchive.ArchiveError.encryptionContextFailed,
            BackupArchive.ArchiveError.decryptionStreamFailed,
            BackupArchive.ArchiveError.missingHeaderField("PAT(string)"),
            BackupArchive.ArchiveError.entryTooLarge(path: "private/StudentEntity.ndjson", size: 134_030),
            BackupArchive.ArchiveError.sizeMismatch(expected: 25_300, actual: 36),
            BackupArchive.ArchiveError.underlying(Boom()),
            BackupReader.ReadError.notArchiveFormat,
            BackupReader.ReadError.manifestMissing,
            BackupReader.ReadError.manifestMalformed(reason: "manifest did not round-trip"),
            BackupReader.ReadError.entryPathInvalid("private/StudentEntity.ndjson"),
            BackupReader.ReadError.unsupportedFormatVersion(found: 40, supported: 17...36),
            BackupWriter.WriterError.entityEncodingFailed(entityName: "StudentEntity", underlying: Boom()),
            BackupWriter.WriterError.verificationFailed("manifest did not round-trip"),
            BackupWriter.WriterError.photoUnreadable(filename: "photo-17.heic", underlying: Boom()),
            BackupEncryptionKeyStore.KeyStoreError.keychainRead(-25_300),
            BackupEncryptionKeyStore.KeyStoreError.keychainWrite(-25_300),
            BackupEncryptionKeyStore.KeyStoreError.keyUnavailableForRestore,
            BackupDestination.FolderRejection.insideGitRepository(Self.path),
            BackupDestination.FolderRejection.insideAppBundle(Self.path),
            BackupDestination.FolderRejection.systemProtected(Self.path),
            AutoBackupManager.AlreadyRunning()
        ]
        for error in errors {
            expectPlain(error)
        }
    }

    @Test("A newer backup asks for an update; an older or foreign file says it isn't one")
    func formatVersions() {
        #expect(BackupReader.ReadError.unsupportedFormatVersion(found: 40, supported: 17...36).errorDescription
            == "This backup was made by a newer version of Cosmic Daybook. Update the app, then try again.")
        #expect(BackupReader.ReadError.unsupportedFormatVersion(found: 12, supported: 17...36).errorDescription
            == BackupReader.ReadError.notArchiveFormat.errorDescription)
    }

    @Test("A failed restore says what became of the notebook, or what was wrong with the file")
    func restoreOutcomes() {
        typealias Failure = BackupTransactionManager.TransactionError
        #expect(Failure.importFailed(Boom(), checkpointURL: Self.path).errorDescription
            == "The restore didn't finish, so your notebook was put back the way it was. Nothing was lost.")
        #expect(Failure.importFailed(Boom(), checkpointURL: nil).errorDescription
            == "The restore didn't finish, so nothing was changed. Try again.")
        // The file's own fault speaks for itself.
        #expect(Failure.importFailed(BackupReader.ReadError.manifestMissing, checkpointURL: nil).errorDescription
            == "This backup file is damaged and can't be restored.")
        #expect(Failure.checkpointCreationFailed(Boom()).errorDescription
            == "Couldn't make a safety copy before restoring, so nothing was changed. Try again.")
        for error: Error in [
            Failure.importFailed(Boom(), checkpointURL: Self.path), Failure.rollbackFailed(Boom()),
            Failure.noCheckpointExists, Failure.checkpointCreationFailed(Boom()),
            BackupRestoreRun.RunError.notBackedUp("\\BackupPayload.studentEntity")
        ] {
            expectPlain(error)
        }
    }

    @Test("A backup asked for while one runs says so, and nothing about domains or codes")
    func alreadyRunning() {
        let message = AppErrorMessages.backupMessage(
            for: AutoBackupManager.AlreadyRunning(), operation: "back up your notebook"
        )
        #expect(message == "A backup is already running. It'll finish in a moment.")
    }
}
