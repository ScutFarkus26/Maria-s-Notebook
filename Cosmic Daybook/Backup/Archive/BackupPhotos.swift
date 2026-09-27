// BackupPhotos.swift
// Note photos inside the backup archive (format v28).

import CoreData
import Foundation
import OSLog

/// Note photos travel in the backup as their own archive entries,
/// `photos/<filename>`, after every entity entry, holding the photo file's
/// bytes exactly. A note stores only the filename (`CDNote.imagePath`), so a
/// restore puts each photo back under the same name and the restored notes
/// find it.
///
/// Photos are files, not records, so until v28 no backup had them: iCloud kept
/// them safe from a lost device but not from a deleted note. The manifest
/// counts them (`photoCount`) and the read-back verification checks the
/// count, as it does each entity's rows.
///
/// - Which photos: every distinct filename a note names whose file is on this
///   device. One still downloading from iCloud is left out rather than waited
///   for (a backup at quit must not wait on the network); another device's
///   backup has it.
/// - Restore: photos are staged in a temporary folder while the archive is
///   decoded and installed only once the records have imported, never over a
///   photo already there (same name, same photo). A failed restore leaves the
///   photo folder untouched.
/// - Opt-out: `UserDefaultsKeys.backupIncludesNotePhotos` (default on). The
///   safety checkpoint before a restore never carries photos, since a restore
///   never removes one.
nonisolated enum BackupPhotos {
    private static let logger = Logger.backup
    static let pathPrefix = "photos/"

    /// A photo file an export will carry.
    struct File: Sendable, Equatable {
        let name: String
        let url: URL
    }

    /// Whether this device's backups include note photos.
    static var includesNotePhotos: Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.backupIncludesNotePhotos) as? Bool ?? true
    }

    // MARK: Archive paths

    static func archivePath(for filename: String) -> String {
        pathPrefix + filename
    }

    /// The photo filename an archive path names; nil for a path that is not a
    /// photo entry. Throws for a photo entry whose name could reach outside the
    /// photo folder (a separator, `..`, a leading dot) or is empty.
    static func filename(fromArchivePath path: String) throws -> String? {
        guard path.hasPrefix(pathPrefix) else { return nil }
        let name = String(path.dropFirst(pathPrefix.count))
        guard isSafeFilename(name) else { throw BackupReader.ReadError.entryPathInvalid(path) }
        return name
    }

    /// A single path component the photo folder can hold as is.
    static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255
            && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    // MARK: Export

    /// Every distinct photo filename a note names, sorted, read as dictionary
    /// rows (no note objects). Main actor: the view context's queue.
    @MainActor
    static func referencedFilenames(in context: NSManagedObjectContext) -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Note")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["imagePath"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(format: "imagePath != nil AND imagePath != %@", "")
        let rows = (try? context.fetch(request)) ?? []
        let names = rows.compactMap { $0["imagePath"] as? String }.filter(isSafeFilename)
        return Array(Set(names)).sorted()
    }

    /// The photo files for `names` that are on this device, in name order.
    static func localFiles(for names: [String]) -> [File] {
        var files: [File] = []
        var skipped = 0
        for name in names {
            guard let url = PhotoStorageService.photoURL(for: name),
                  !UbiquitousFile.needsDownload(url),
                  FileManager.default.fileExists(atPath: url.path) else {
                skipped += 1
                continue
            }
            files.append(File(name: name, url: url))
        }
        if skipped > 0 {
            logger.notice("Backup leaves out \(skipped, privacy: .public) note photo(s) not on this device")
        }
        return files
    }

    // MARK: Restore

    /// A new, empty folder to stage a restore's photos in.
    static func makeStagingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoredPhotos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Moves every staged photo into the photo folder, skipping a name already
    /// there, then removes the staging folder. Returns how many were installed
    /// and how many could not be. Off the main actor.
    @concurrent
    static func installStaged(from staging: URL) async -> (installed: Int, failed: Int) {
        defer { try? FileManager.default.removeItem(at: staging) }
        let staged = (try? FileManager.default.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        guard !staged.isEmpty else { return (0, 0) }
        let directory: URL
        do {
            directory = try PhotoStorageService.photosDirectory()
        } catch {
            logger.error("Restore couldn't reach the photo folder: \(error.localizedDescription, privacy: .public)")
            return (0, staged.count)
        }
        var installed = 0
        var failed = 0
        for file in staged {
            let name = file.lastPathComponent
            guard PhotoStorageService.photoURL(for: name) == nil else { continue }
            do {
                try UbiquitousFile.coordinatedMove(
                    from: file, to: directory.appendingPathComponent(name, isDirectory: false)
                )
                installed += 1
            } catch {
                failed += 1
                let reason = error.localizedDescription
                logger.warning("Restore couldn't install photo \(name, privacy: .public): \(reason, privacy: .public)")
            }
        }
        logger.notice("Restore installed \(installed, privacy: .public) note photo(s)")
        return (installed, failed)
    }
}
