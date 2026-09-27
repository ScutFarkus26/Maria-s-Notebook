// BackupWriter+VerifiedArchive.swift
// The end every export shares: temp file → verify → atomic move.

import CryptoKit
import Foundation

nonisolated extension BackupWriter {

    /// What `writeVerifiedArchive` needs besides the entity entries.
    struct ArchiveJob: Sendable {
        let manifest: BackupArchiveManifest
        let manifestData: Data
        let preferencesData: Data
        let encryptionKey: SymmetricKey
        let url: URL
        let stopsWhenCancelled: Bool
    }

    /// Writes `manifest.json`, `preferences.json` and whatever `appendEntities`
    /// adds to a hidden temp file beside `job.url`, re-reads it
    /// (`verifyStructure`), and moves it into place. Any failure — a stopped
    /// background export included — removes the temp file, so nothing
    /// unverified ever reaches the destination. Returns the entity-entry count
    /// `appendEntities` reports. Runs on its caller's executor; both callers
    /// are `@concurrent`.
    static func writeVerifiedArchive(
        _ job: ArchiveJob,
        progress: @escaping BackupService.ProgressCallback,
        appendEntities: (BackupArchive.Appender) throws -> Int
    ) async throws -> Int {
        // Hidden temp file in the destination directory (same volume, so the
        // final move is an atomic rename — also under any security scope the
        // caller holds for that folder).
        let tempURL = job.url.deletingLastPathComponent()
            .appendingPathComponent(".\(job.url.lastPathComponent).partial-\(UUID().uuidString)")

        var writtenEntryCount = 0
        do {
            try BackupArchive.write(to: tempURL, encryptionKey: job.encryptionKey) { appender in
                // Manifest first so readers can stream-validate.
                try appender.append(path: "manifest.json", data: job.manifestData)
                // Preferences as a single JSON document (not NDJSON).
                try appender.append(path: "preferences.json", data: job.preferencesData)
                writtenEntryCount = try appendEntities(appender)
            }

            // Verification re-reads the whole archive, and an unverified file
            // never moves into place, so a stopping export ends here too.
            if job.stopsWhenCancelled { try Task.checkCancellation() }
            await progress(0.9, "Verifying\u{2026}")
            BackupPipelineProbe.reach("verify")
            try verifyWrittenArchive(at: tempURL, encryptionKey: job.encryptionKey, expected: job.manifest)
            try moveIntoPlace(from: tempURL, to: job.url)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return writtenEntryCount
    }

    /// Re-reads the just-written archive and checks that the manifest decodes
    /// to what was intended and every entity entry holds exactly the promised
    /// number of NDJSON rows. Catches truncation, encode bugs, and disk-level
    /// corruption before the file ever reaches the destination.
    private static func verifyWrittenArchive(
        at url: URL,
        encryptionKey: SymmetricKey,
        expected: BackupArchiveManifest
    ) throws {
        let verification = try BackupReader.verifyStructure(at: url) { encryptionKey }

        guard verification.manifest.formatVersion == expected.formatVersion,
              verification.manifest.entityCounts == expected.entityCounts,
              verification.manifest.originStores == expected.originStores else {
            throw WriterError.verificationFailed("manifest did not round-trip")
        }
        for (entityName, expectedCount) in expected.entityCounts {
            let actual = verification.entryLineCounts[entityName] ?? 0
            guard actual == expectedCount else {
                throw WriterError.verificationFailed(
                    "\(entityName): wrote \(expectedCount) records, read back \(actual)"
                )
            }
        }
    }

    /// The rename that makes the backup appear under its real name. The usual
    /// destination is the iCloud Drive backups folder, so it is a coordinated
    /// write (see `UbiquitousFile`): iCloud sees one finished file arrive.
    private static func moveIntoPlace(from tempURL: URL, to url: URL) throws {
        let fileManager = FileManager.default
        try UbiquitousFile.coordinatedReplace(at: url) { target in
            do {
                try fileManager.moveItem(at: tempURL, to: target)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                _ = try fileManager.replaceItemAt(target, withItemAt: tempURL)
            }
        }
    }
}
