// BackupEntityImporter+LessonFiles.swift
// Lesson files on a merge restore. A backup carries each attachment's record
// but never its file, nor its bookmark (BACKUP_SYSTEM.md), so a row from an
// older backup can name a file that a replace or a rename has since sent to
// the Trash or moved, while the record's bookmark, which a restore leaves
// alone, still finds the live one.

import CoreData
import Foundation

/// Where a restore looks for lesson files.
nonisolated enum BackupLessonFiles {
    /// The Lesson Files folder a merge checks a row's file in; tests bind a
    /// scratch one with `$storage.withValue`.
    @TaskLocal static var storage: ManagedPDFFileStorage = LessonFileStorage.storage

    /// Whether `relativePath` names a file in `storage` that is on this device
    /// or waiting in iCloud to come down. An empty path names none.
    static func isPresent(_ relativePath: String, in storage: ManagedPDFFileStorage) -> Bool {
        guard !relativePath.trimmed().isEmpty,
              let url = try? storage.resolve(relativePath: relativePath) else { return false }
        return UbiquitousFile.isAvailable(url)
    }
}

extension BackupEntityImporter {

    /// The keys of a lesson-file row that describe its file.
    static let lessonFileKeys = ["fileRelativePath", "fileName", "fileSizeBytes", "fileType"]

    /// `rows` as a merge lays them over the lesson files already here. A row
    /// whose file is neither on this device nor waiting in iCloud, for a record
    /// whose own file is, keeps the record's file: its path, name, size and
    /// type, and its `modifiedAt` when that is the later. The rest of the row
    /// (the note, the scope, the lesson) is restored as usual, and a row whose
    /// file is still here is restored as it is. Without this the record would
    /// name a file in the Trash, the iPad (which finds the file by its path)
    /// would find nothing, and the live file would belong to no record.
    ///
    /// `existing` is the record the row updates (none in a Replace, whose
    /// clear came first); `isPresent` says whether a stored path names a file.
    static func keepingLiveLessonFiles(
        _ rows: [LessonAttachmentDTO],
        existing: (UUID) -> CDLessonAttachment?,
        isPresent: (String) -> Bool
    ) -> [LessonAttachmentDTO] {
        rows.map { row in
            guard let record = existing(row.id) else { return row }
            let backedUp = row.string("fileRelativePath") ?? ""
            let live = record.fileRelativePath
            guard LessonFileStorage.pathKey(backedUp) != LessonFileStorage.pathKey(live),
                  !isPresent(backedUp), isPresent(live),
                  let current = LessonAttachmentDTO(record) else { return row }
            var kept = row
            for key in lessonFileKeys {
                kept.values[key] = current.values[key]
            }
            if case .date(let liveChange)? = current.values["modifiedAt"] {
                let rowChange: Date? = if case .date(let date)? = row.values["modifiedAt"] { date } else { nil }
                if rowChange.map({ $0 < liveChange }) ?? true {
                    kept.values["modifiedAt"] = .date(liveChange)
                }
            }
            return kept
        }
    }
}
