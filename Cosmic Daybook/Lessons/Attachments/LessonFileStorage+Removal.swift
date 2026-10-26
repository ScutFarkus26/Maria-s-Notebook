//
//  LessonFileStorage+Removal.swift
//  Cosmic Daybook
//
//  When a lesson file may leave the disk, and how.
//
//  Lesson files live in iCloud Drive, so removing one reaches every device.
//  The rules (Danny, 2026-10-10): a file goes only after the save that
//  dropped its record has succeeded, only when no other record still points
//  at it (another lesson's Pages file or attachment), and to the Trash rather
//  than straight to deletion. In the Sample Class nothing on disk is touched:
//  its lessons are copies that point at the real notebook's files, and while
//  it shows, the real notebook keeps the files they use (`showingSampleClass`).
//

import CoreData
import Foundation
import OSLog

extension LessonFileStorage {

    /// A stored relative path folded for comparison: standardized, without a
    /// leading slash, and lowercased (the volume ignores case, so two
    /// spellings name one file, and a false match only keeps a file).
    nonisolated static func pathKey(_ relativePath: String) -> String {
        var path = (relativePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).standardizingPath
        while path.hasPrefix("/") { path.removeFirst() }
        return path.lowercased()
    }

    /// The relative path of the lesson's own Pages file when it sits in the
    /// managed folder (an older lesson may hold only a bookmark).
    static func managedPagesPath(of lesson: CDLesson) -> String? {
        if let rel = lesson.pagesFileRelativePath?.trimmed(), !rel.isEmpty { return rel }
        guard let bookmark = lesson.pagesFileBookmark,
              let url = try? SecurityScopedBookmark.resolve(bookmark, options: [.withoutUI]).url,
              isManagedURL(url) else { return nil }
        return try? relativePath(forManagedURL: url)
    }

    /// The Sample Class's records while it is showing. Its lessons are copies
    /// that point at the real notebook's files (`SampleClassroomSeeder`), so
    /// while it shows, a change in the real notebook (one of Claude's, over
    /// MCP) must neither trash nor move a file one of them uses. Set by
    /// `ClassroomWorkspaceStore` as the Sample Class shows and cleared as it
    /// leaves; each time it opens, its copies are pointed at the files as they
    /// are then, so while it isn't showing nothing of its needs keeping.
    static weak var showingSampleClass: NSManagedObjectContext?

    /// The files among `relativePaths` that no lesson's Pages file and no
    /// attachment in `context` points at any more, `apartFrom` aside, nor any
    /// in `others` (nil: the Sample Class while it shows). Call it after the
    /// save that dropped the references, so a failed save never loses a file.
    /// `storage` is the Lesson Files folder unless a test passes its own.
    static func unreferencedFiles(
        _ relativePaths: [String],
        in context: NSManagedObjectContext,
        storage: ManagedPDFFileStorage = LessonFileStorage.storage,
        apartFrom attachment: CDLessonAttachment? = nil,
        alsoIn others: [NSManagedObjectContext]? = nil
    ) -> [URL] {
        var wanted: [String: String] = [:]
        for path in relativePaths where !path.trimmed().isEmpty {
            let key = pathKey(path)
            if wanted[key] == nil { wanted[key] = path }
        }
        guard !wanted.isEmpty else { return [] }

        var referenced = referencedPaths(in: context, apartFrom: attachment)
        for other in others ?? showingSampleClass.map({ [$0] }) ?? [] where other !== context {
            referenced.formUnion(referencedPaths(in: other, apartFrom: nil))
        }

        return wanted.filter { !referenced.contains($0.key) }
            .values.sorted()
            .compactMap { try? storage.resolve(relativePath: $0) }
    }

    /// The files (`pathKey`) that `context`'s lessons' Pages files and its
    /// attachments, `attachment` aside, point at.
    private static func referencedPaths(
        in context: NSManagedObjectContext, apartFrom attachment: CDLessonAttachment?
    ) -> Set<String> {
        var referenced = Set<String>()
        let lessons = CDFetchRequest(CDLesson.self)
        lessons.predicate = NSPredicate(format: "pagesFileRelativePath != nil AND pagesFileRelativePath != ''")
        for lesson in context.safeFetch(lessons) where !lesson.isDeleted {
            referenced.insert(pathKey(lesson.pagesFileRelativePath ?? ""))
        }
        let attachments = CDFetchRequest(CDLessonAttachment.self)
        attachments.predicate = NSPredicate(format: "fileRelativePath != ''")
        for record in context.safeFetch(attachments) where !record.isDeleted && record !== attachment {
            referenced.insert(pathKey(record.fileRelativePath))
        }
        return referenced
    }

    /// After a save that dropped references to `relativePaths`: moves the ones
    /// nothing else uses to the Trash. Does nothing in the Sample Class.
    static func trashUnreferencedFiles(
        _ relativePaths: [String], in context: NSManagedObjectContext, isSampleClassroom: Bool
    ) {
        guard !isSampleClassroom else { return }
        moveToTrash(unreferencedFiles(relativePaths, in: context))
    }

    /// Moves managed files to the Trash (never straight to deletion), off the
    /// main thread and coordinated with iCloud. A file that can't be moved is
    /// logged and left where it is: a stray file costs nothing, a lost one does.
    /// Only files inside `storage`'s folder are moved.
    nonisolated static func moveToTrash(
        _ urls: [URL], in storage: ManagedPDFFileStorage = LessonFileStorage.storage
    ) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls { LessonFileStorage.moveToTrashNow(url, in: storage) }
        }
    }

    nonisolated private static func moveToTrashNow(_ url: URL, in storage: ManagedPDFFileStorage) {
        guard storage.isManagedURL(url), UbiquitousFile.isAvailable(url) else { return }
        var coordinationError: NSError?
        var trashError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError
        ) { target in
            do {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            } catch {
                trashError = error
            }
        }
        if let error = coordinationError ?? trashError {
            Logger.lessons.warning("Couldn't move a lesson file to the Trash: \(error.localizedDescription)")
        }
    }
}
