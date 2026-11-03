// BackupWriter+VerifiedArchive.swift
// The end every export shares: temp file → verify → atomic move.

import CryptoKit
import Foundation
import OSLog

nonisolated extension BackupWriter {

    /// What `writeVerifiedArchive` needs besides the entity entries.
    struct ArchiveJob: Sendable {
        let manifest: BackupArchiveManifest
        let manifestData: Data
        let preferencesData: Data
        let encryptionKey: SymmetricKey
        let url: URL
        let stopsWhenCancelled: Bool
        /// Note photos appended after the entity entries (v28; `BackupPhotos`).
        var photos: [BackupPhotos.File] = []
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
        // What an export stopped by a kill or a suspension left behind: the
        // removal below never ran for it (bug hunt 2026-11-02 #17).
        removeAbandonedTempFiles(in: job.url.deletingLastPathComponent())
        // Hidden temp file in the destination directory (same volume, so the
        // final move is an atomic rename — also under any security scope the
        // caller holds for that folder).
        let tempURL = tempFileURL(for: job.url)

        var writtenEntryCount = 0
        do {
            try BackupArchive.write(to: tempURL, encryptionKey: job.encryptionKey) { appender in
                // Manifest first so readers can stream-validate.
                try appender.append(path: "manifest.json", data: job.manifestData)
                // Preferences as a single JSON document (not NDJSON).
                try appender.append(path: "preferences.json", data: job.preferencesData)
                writtenEntryCount = try appendEntities(appender)
                try appendPhotos(job, to: appender)
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

    // MARK: - Temp files

    /// The hidden file an export of `url` is written to before it is checked
    /// and moved into place: `.<name>.partial-<UUID>` beside it.
    static func tempFileURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent)\(tempMarker)\(UUID().uuidString)")
    }

    private static let tempMarker = ".partial-"

    /// How old a temp file must be before an export takes it for abandoned.
    /// No export runs this long, so another device's or process's export
    /// still writing into the same iCloud folder is never touched.
    static let abandonedTempAge: TimeInterval = 60 * 60

    /// Deletes the temp files exports left in `folder` (`tempFileURL`) that
    /// haven't changed for `abandonedTempAge`. A kill mid-write (the Mac's
    /// quit limit, an iPad suspended during its export) skips the removal
    /// `writeVerifiedArchive` does on an error, and every listing skips hidden
    /// files, so each one stayed for good: a full-size archive in iCloud
    /// Drive. Nothing else in the folder is touched. Returns how many went.
    @discardableResult
    static func removeAbandonedTempFiles(
        in folder: URL,
        now: Date = Date(),
        delete: (URL) throws -> Void = UbiquitousFile.coordinatedDelete
    ) -> Int {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        )) ?? []
        var removed = 0
        for url in entries where isTempFileName(url.lastPathComponent) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            guard now.timeIntervalSince(modified) >= abandonedTempAge else { continue }
            do {
                try delete(url)
                removed += 1
            } catch {
                Logger.backup.warning("""
                    Couldn't remove an abandoned backup temp file \(url.lastPathComponent, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        if removed > 0 {
            Logger.backup.notice(
                "Removed \(removed, privacy: .public) backup temp file(s) an earlier export left behind"
            )
        }
        return removed
    }

    /// `.<name>.\(BackupFile.fileExtension).partial-<anything>`: a name only
    /// `tempFileURL` makes.
    static func isTempFileName(_ name: String) -> Bool {
        guard name.hasPrefix("."), let marker = name.range(of: tempMarker, options: .backwards) else {
            return false
        }
        return name[..<marker.lowerBound].hasSuffix(".\(BackupFile.fileExtension)")
    }

    // MARK: - Photos

    /// Each photo file's bytes as a `photos/<filename>` entry, one file in
    /// memory at a time. A photo that can't be read aborts the export: a
    /// backup whose manifest promises a photo it lacks would fail verification
    /// anyway, and one silently missing it would look complete.
    private static func appendPhotos(_ job: ArchiveJob, to appender: BackupArchive.Appender) throws {
        for photo in job.photos {
            if job.stopsWhenCancelled { try Task.checkCancellation() }
            try autoreleasepool {
                let data: Data
                do {
                    data = try Data(contentsOf: photo.url, options: .mappedIfSafe)
                } catch {
                    throw WriterError.photoUnreadable(filename: photo.name, underlying: error)
                }
                try appender.append(path: BackupPhotos.archivePath(for: photo.name), data: data)
            }
        }
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
        guard verification.photoCount == (expected.photoCount ?? 0) else {
            throw WriterError.verificationFailed(
                "wrote \(expected.photoCount ?? 0) photos, read back \(verification.photoCount)"
            )
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
