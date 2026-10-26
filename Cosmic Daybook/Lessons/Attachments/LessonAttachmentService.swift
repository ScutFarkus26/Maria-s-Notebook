//
//  LessonAttachmentService.swift
//  Cosmic Daybook
//
//  The one writer of lesson attachments. The Files card and the MCP tools
//  add, replace, rename, annotate and remove a lesson's files through it
//  (plan "Lesson file attachments", Phase 1).
//

import CoreData
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Adds, replaces, renames, annotates and removes a lesson's attachments.
///
/// The file rules it keeps (`UbiquitousFile`, `LessonFileStorage+Removal`):
/// - A file in Lesson Files is written once under a new name and never
///   rewritten in place. A replace copies the new file in under a name the
///   attachment never had (numbered past the old file's), saves the record
///   pointing at it, and only then sends the old file to the Trash; it never
///   deletes first.
/// - A file leaves the disk only after the save that dropped its record, only
///   when nothing else points at it, and to the Trash.
/// - A failed save takes back exactly this change (`ContextMutationTransaction`,
///   so the guide's other unsaved edits stay) and removes any copy made for it.
/// - The Sample Class can't add or replace files: its lessons point at the
///   real notebook's files. A rename, a note or a removal there changes the
///   record only.
///
/// `fileName` keeps the title as given ("Area of a Circle — remade album
/// pages.pdf"); only the name on disk is sanitized.
@MainActor
final class LessonAttachmentService {
    private static let logger = Logger.lessons

    /// The largest file that can be attached: 50 MB, counted the way the Files
    /// card shows sizes (`ByteCountFormatter`'s file style, 1 MB = 1,000,000 bytes).
    nonisolated static let maximumFileSize: Int64 = 50_000_000

    /// Any file. The Files card has always taken whatever it was given (its
    /// picker offers PDFs, images and Pages documents; a drop can carry any
    /// file), so for it only the size limit is checked.
    nonisolated static let anyFile: [UTType] = [.item]

    /// PDFs and images, each checked by its content as well as its name.
    nonisolated static let pdfOrImage: [UTType] = [.pdf, .image]

    /// How long a replace waits for the old file to come down from iCloud to
    /// compare it with the new one. The comparison only spares a needless
    /// copy, so a file that takes longer is replaced without it.
    nonisolated static let comparisonTimeout: Duration = .seconds(15)

    // `Problem`, `CheckedFile` and `validate(fileAt:allowedTypes:)` are in
    // +Checks; `existingAttachment(titled:on:)` and the title helpers in +Titles.

    /// What a replace did.
    enum ReplaceOutcome: Equatable {
        /// The record now holds a copy of the new file; the old file went to
        /// the Trash (when nothing else uses it).
        case replaced
        /// The new file has the same bytes as the old one, and only the note
        /// changed.
        case noteChanged
        /// The same bytes and the same note: nothing was written.
        case unchanged
    }

    let context: NSManagedObjectContext
    let storage: ManagedPDFFileStorage
    let isSampleClassroom: Bool
    private let save: (NSManagedObjectContext) throws -> Void
    private let trash: ([URL]) -> Void
    private let otherNotebooks: () -> [NSManagedObjectContext]

    /// - Parameters:
    ///   - storage: the Lesson Files folder; tests pass a scratch one.
    ///   - isSampleClassroom: the Sample Class's store, whose files are the
    ///     real notebook's.
    ///   - save: how the context is saved; tests make it fail.
    ///   - trash: where files nothing uses any more go, after the save that let
    ///     go of them. Nil: the Trash, through `LessonFileStorage.moveToTrash`.
    ///   - otherNotebooks: other stores open here whose records use these same
    ///     files; a file one of them uses is never trashed, and a rename copies
    ///     it rather than take it from them. Nil: the Sample Class while it
    ///     shows (`LessonFileStorage.showingSampleClass`).
    init(
        context: NSManagedObjectContext,
        storage: ManagedPDFFileStorage = LessonFileStorage.storage,
        isSampleClassroom: Bool = false,
        save: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() },
        trash: (([URL]) -> Void)? = nil,
        otherNotebooks: (() -> [NSManagedObjectContext])? = nil
    ) {
        self.context = context
        self.storage = storage
        self.isSampleClassroom = isSampleClassroom
        self.save = save
        self.trash = trash ?? { LessonFileStorage.moveToTrash($0, in: storage) }
        self.otherNotebooks = otherNotebooks ?? { LessonFileStorage.showingSampleClass.map { [$0] } ?? [] }
    }

    // MARK: - Adding

    /// Copies the file into the lesson's folder and attaches it with `scope`.
    /// `title` (as given, trimmed) is what the card shows, with the file's
    /// extension added when it has none; nil keeps the file's own name. Only
    /// the copy's name on disk is sanitized. When the save fails, the copy is
    /// removed and nothing is left behind.
    ///
    /// `confirmingSource` is a last look at the file about to be copied, given
    /// where it really is (symbolic links followed), right before the copy; it
    /// throws to refuse it. The MCP tools pass their folder check
    /// (`MCPAttachFolders.Recheck`), so a file swapped for a link leading out
    /// of the guide's folders after the path was checked is never read.
    @discardableResult
    func add(
        fileAt url: URL,
        to lesson: CDLesson,
        scope: AttachmentScope = .lesson,
        title: String? = nil,
        notes: String = "",
        allowedTypes: [UTType],
        confirmingSource: (URL) throws -> Void = { _ in }
    ) throws -> CDLessonAttachment {
        guard !isSampleClassroom else { throw Problem.sampleClass }
        guard !lesson.isDeleted, lesson.managedObjectContext != nil else { throw Problem.noLesson }
        let checked = try Self.validate(fileAt: url, allowedTypes: allowedTypes)
        let ext = checked.url.pathExtension
        let givenTitle = title?.trimmed()
        let named = givenTitle.flatMap { $0.isEmpty ? nil : $0 }
        let fileName = named.map { Self.fileName(title: $0, ext: ext) } ?? checked.url.lastPathComponent

        try confirmingSource(checked.url)
        let copy = try LessonFileStorage.importAttachment(
            from: checked.url,
            forLesson: lesson,
            scope: scope,
            customName: named.map { CDLessonAttachment.titleStem(of: $0, fileType: ext) },
            in: storage
        )
        do {
            let bookmark = try storage.makeBookmark(for: copy.url)
            return try commit { () -> CDLessonAttachment in
                let attachment = CDLessonAttachment(context: context)
                attachment.fileName = fileName
                attachment.fileBookmark = bookmark
                attachment.fileRelativePath = copy.relativePath
                attachment.fileType = ext.lowercased()
                attachment.fileSizeBytes = checked.size
                attachment.scope = scope
                attachment.notes = notes.trimmed()
                attachment.lesson = lesson
                return attachment
            }
        } catch {
            // Nothing points at the copy just made, so it can go.
            removeCopy(copy.url)
            throw error
        }
    }

    // MARK: - Replacing

    /// Gives `attachment` the file at `url` in place of its own: the same
    /// record (and id), a copy of the new file under a new name in the
    /// lesson's folder, a fresh bookmark, the new size and type, no thumbnail,
    /// `notes` when given, and a new `modifiedAt`. Saved first; the old file
    /// goes to the Trash only after the save, and only when nothing else uses
    /// it. A failed save removes the new copy and leaves the record and the
    /// old file as they were.
    ///
    /// When the old file is on this device (or comes down within
    /// `comparisonTimeout`) and has the same bytes, nothing is copied, and
    /// with the same note nothing is written at all (`.unchanged`). A missing
    /// old file is no obstacle. Hold any security-scoped access `url` needs
    /// until this returns. `confirmingSource` is as for `add`, and runs twice:
    /// before the comparison reads the new file, and again right before the
    /// copy, since the comparison can wait for iCloud.
    func replace(
        _ attachment: CDLessonAttachment,
        withFileAt url: URL,
        notes: String? = nil,
        allowedTypes: [UTType],
        confirmingSource: (URL) throws -> Void = { _ in }
    ) async throws -> ReplaceOutcome {
        guard !isSampleClassroom else { throw Problem.sampleClass }
        guard isLive(attachment) else { throw Problem.noLesson }
        let checked = try Self.validate(fileAt: url, allowedTypes: allowedTypes)
        try confirmingSource(checked.url)
        let comparedPath = attachment.fileRelativePath
        let sameBytes = await hasSameBytes(relativePath: comparedPath, as: checked.url)

        // Anything could have happened to the record while the comparison waited.
        guard isLive(attachment) else { throw Problem.noLesson }
        let oldPath = attachment.fileRelativePath
        let newNotes = notes?.trimmed()
        let notesChange = newNotes.map { $0 != attachment.notes } ?? false

        if sameBytes, oldPath == comparedPath {
            guard notesChange, let newNotes else { return .unchanged }
            try commit {
                attachment.notes = newNotes
                attachment.modifiedAt = Date()
            }
            return .noteChanged
        }

        let title = attachment.title
        let ext = checked.url.pathExtension
        // A name this attachment never had, numbered past the old file's: not
        // the old one (still on disk, or held by this record when it hasn't
        // arrived yet), nor one an earlier replace sent to the Trash.
        try confirmingSource(checked.url)
        let copy = try LessonFileStorage.importReplacement(
            from: checked.url, for: attachment, title: title, in: storage
        )
        do {
            let bookmark = try storage.makeBookmark(for: copy.url)
            try commit {
                if ext.lowercased() != attachment.fileType.lowercased() {
                    attachment.fileName = Self.fileName(title: title, ext: ext)
                }
                attachment.fileRelativePath = copy.relativePath
                attachment.fileBookmark = bookmark
                attachment.fileType = ext.lowercased()
                attachment.fileSizeBytes = checked.size
                attachment.thumbnailData = nil
                if let newNotes { attachment.notes = newNotes }
                attachment.modifiedAt = Date()
            }
        } catch {
            removeCopy(copy.url)
            throw error
        }
        trashUnreferenced([oldPath])
        return .replaced
    }

    // MARK: - Renaming, notes, removing

    /// Renames the attachment: the record keeps `requestedName` as typed (with
    /// the file's extension added when it has none), and the file on disk
    /// takes its sanitized form. In the Sample Class, or for a record with no
    /// file, only the record changes. A file another record also uses (a
    /// synced copy, the Sample Class's while it shows) is copied to the new
    /// name and left where it is for them; when its bytes aren't on this
    /// device to copy, only the record changes, as in the Sample Class. When
    /// the save fails, the record and the file go back to their old names and
    /// a copy is removed. Returns whether anything changed.
    @discardableResult
    func rename(_ attachment: CDLessonAttachment, to requestedName: String) throws -> Bool {
        let typed = requestedName.trimmed()
        guard !typed.isEmpty else { throw Problem.emptyName }
        if isSampleClassroom || attachment.fileRelativePath.trimmed().isEmpty {
            return try renameRecord(attachment, to: typed)
        }

        let oldPath = attachment.fileRelativePath
        let oldURL = try storage.resolve(relativePath: oldPath)
        let shared = LessonFileStorage.unreferencedFiles(
            [oldPath], in: context, storage: storage, apartFrom: attachment, alsoIn: otherNotebooks()
        ).isEmpty
        if shared, UbiquitousFile.needsDownload(oldURL) {
            // A copy would wait on the main thread for iCloud.
            let named = URL(fileURLWithPath: typed).pathExtension.isEmpty && !attachment.fileType.isEmpty
                ? typed + "." + attachment.fileType : typed
            return try renameRecord(attachment, to: named)
        }
        let renamed = try LessonFileStorage.renameAttachment(
            attachment, to: typed, keepingOriginal: shared, in: storage
        )
        let changedFile = oldURL.standardizedFileURL != renamed.url.standardizedFileURL
        guard changedFile || renamed.fileName != attachment.fileName || renamed.fileType != attachment.fileType else {
            return false
        }
        do {
            let bookmark = try storage.makeBookmark(for: renamed.url)
            try commit {
                attachment.fileName = renamed.fileName
                attachment.fileRelativePath = renamed.relativePath
                attachment.fileBookmark = bookmark
                attachment.fileType = renamed.fileType
                attachment.modifiedAt = Date()
            }
        } catch {
            if changedFile {
                if shared { removeCopy(renamed.url) } else { moveBack(renamed.url, to: oldURL) }
            }
            throw error
        }
        return true
    }

    /// Gives the record `name` and leaves its file as it is.
    private func renameRecord(_ attachment: CDLessonAttachment, to name: String) throws -> Bool {
        guard name != attachment.fileName else { return false }
        try commit {
            attachment.fileName = name
            attachment.modifiedAt = Date()
        }
        return true
    }

    /// Sets the attachment's note (where the file came from, say), trimmed.
    /// Returns whether it changed; an unchanged note writes nothing.
    @discardableResult
    func setNotes(_ attachment: CDLessonAttachment, _ notes: String) throws -> Bool {
        let trimmed = notes.trimmed()
        guard trimmed != attachment.notes else { return false }
        try commit {
            attachment.notes = trimmed
            attachment.modifiedAt = Date()
        }
        return true
    }

    /// Deletes the attachment's record, and clears it as its lesson's primary
    /// file when it was that. After the save its file goes to the Trash when
    /// nothing else points at it; in the Sample Class only the record goes.
    func remove(_ attachment: CDLessonAttachment) throws {
        let holder = attachment.lesson
        let wasPrimary = attachment.id != nil && holder?.primaryAttachmentIDUUID == attachment.id
        let path = attachment.fileRelativePath
        try commit {
            if wasPrimary { holder?.primaryAttachmentID = nil }
            context.delete(attachment)
        }
        trashUnreferenced([path])
    }

    // MARK: - Helpers

    /// Runs `change` and saves. A failed save (or a `change` that throws)
    /// takes back exactly this change and throws `Problem.saveFailed`.
    @discardableResult
    private func commit<T>(_ change: () throws -> T) throws -> T {
        let transaction = ContextMutationTransaction(context: context)
        do {
            let result = try change()
            try save(context)
            transaction.commit()
            return result
        } catch {
            Self.logger.error("Couldn't save a lesson file change: \(error.localizedDescription, privacy: .public)")
            transaction.rollback()
            throw Problem.saveFailed
        }
    }

    /// Still a record of this context, held by a lesson.
    private func isLive(_ attachment: CDLessonAttachment) -> Bool {
        guard !attachment.isDeleted, attachment.managedObjectContext != nil,
              let lesson = attachment.lesson, !lesson.isDeleted else { return false }
        return true
    }

    /// After the save that let go of `paths`: the files nothing else uses go
    /// to the Trash, nothing in this notebook and nothing in `otherNotebooks`
    /// (the Sample Class while it shows). Never in the Sample Class.
    private func trashUnreferenced(_ paths: [String]) {
        guard !isSampleClassroom else { return }
        let unused = LessonFileStorage.unreferencedFiles(
            paths, in: context, storage: storage, alsoIn: otherNotebooks()
        )
        if !unused.isEmpty { trash(unused) }
    }

    /// Removes a copy made for a change that didn't save. Nothing points at it.
    private func removeCopy(_ url: URL) {
        do {
            try storage.deleteIfManaged(url)
        } catch {
            Self.logger.warning("Couldn't remove an unsaved lesson file copy: \(error.localizedDescription)")
        }
    }

    /// Puts a renamed file back under its old name after the save failed.
    private func moveBack(_ url: URL, to oldURL: URL) {
        do {
            try UbiquitousFile.coordinatedMove(from: url, to: oldURL)
        } catch {
            Self.logger.warning("Couldn't put a renamed lesson file back: \(error.localizedDescription)")
        }
    }
}
