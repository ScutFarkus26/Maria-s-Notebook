import Foundation
import OSLog
import CoreData

/// File storage for lesson files and attachments under `Documents/Lesson Files/`
/// (visible in Finder as iCloud Drive/Cosmic Daybook/Lesson Files). A façade over
/// one `ManagedPDFFileStorage` for the shared directory, bookmark and path
/// operations; the Area/Sequence organizational tree, scope-prefixed attachment
/// names and renaming are lesson-specific and live here.
public enum LessonFileStorage {
    static let logger = Logger.lessons

    nonisolated static let storage = ManagedPDFFileStorage(
        folderName: "Lesson Files",
        fallbackBaseName: "Lesson",
        localFallbackWarning: "iCloud not available, using local Documents",
        logger: .lessons
    )

    // MARK: - Result Types

    /// Metadata returned after a successful attachment rename.
    struct RenameAttachmentResult {
        let url: URL
        let relativePath: String
        /// The name as it was typed, with the file's extension when it had
        /// none; only the file on disk (`url`) has a sanitized name.
        let fileName: String
        let fileType: String
    }

    /// Returns the root directory URL where lesson files are stored, creating it if needed.
    public static func lessonFilesDirectory() throws -> URL {
        try storage.directory()
    }

    /// Returns true if the given URL is inside the managed lesson files directory.
    public static func isManagedURL(_ url: URL) -> Bool {
        storage.isManagedURL(url)
    }

    /// Deletes the item at the given URL if it is inside the managed lesson files directory.
    /// Does nothing if the URL is not managed or does not exist.
    public static func deleteIfManaged(_ url: URL) throws {
        try storage.deleteIfManaged(url)
    }

    /// Imports a file or package directory from a source URL into the managed lesson files directory.
    /// The destination filename is the sanitized lesson name plus the source file extension,
    /// numbered on collision. Returns the final destination URL.
    public static func importFile(
        from sourceURL: URL,
        forLessonWithID lessonID: UUID,
        lessonName: String?
    ) throws -> URL {
        let destDir = try lessonFilesDirectory()
        let sourceExt = sourceURL.pathExtension
        let destinationURL = storage.uniqueDestination(
            in: destDir,
            baseName: storage.sanitizedBaseName(lessonName?.trimmed()),
            extWithDot: sourceExt.isEmpty ? "" : "." + sourceExt
        )
        try UbiquitousFile.coordinatedCopy(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Creates a standard bookmark Data for the given URL without security scope.
    public static func makeBookmark(for url: URL) throws -> Data {
        try storage.makeBookmark(for: url)
    }

    /// Returns a relative path string for a managed URL, relative to the lesson files directory.
    public static func relativePath(forManagedURL url: URL) throws -> String {
        try storage.relativePath(forManagedURL: url)
    }

    /// Resolves a relative path (previously returned by `relativePath(forManagedURL:)`)
    /// to an absolute URL inside the managed directory.
    public static func resolve(relativePath: String) throws -> URL {
        try storage.resolve(relativePath: relativePath)
    }

    // MARK: - Organizational Structure

    /// Returns the organizational path for a lesson: Area/Sequence
    /// Creates the directory structure if it doesn't exist. `storage` is the
    /// Lesson Files folder unless a test passes its own.
    static func organizationalDirectory(
        forLesson lesson: CDLesson, in storage: ManagedPDFFileStorage = LessonFileStorage.storage
    ) throws -> URL {
        logger.debug("Getting lesson files directory...")
        let baseDir = try storage.directory()
        logger.debug("Base directory: \(baseDir.path)")

        let sanitizedArea = ManagedPDFFileStorage.sanitizeFilenameComponent(lesson.area, fallback: "General")
        let sanitizedSequence = ManagedPDFFileStorage.sanitizeFilenameComponent(lesson.sequence, fallback: "Ungrouped")
        logger.debug("Sanitized area: '\(sanitizedArea)', sequence: '\(sanitizedSequence)'")

        let orgDir = baseDir
            .appendingPathComponent(sanitizedArea, isDirectory: true)
            .appendingPathComponent(sanitizedSequence, isDirectory: true)

        logger.debug("Creating directory at: \(orgDir.path)")
        try storage.createDirectoryIfNeeded(at: orgDir)
        logger.debug("Directory created/exists")
        return orgDir
    }

    /// Returns a lesson's attachments: its own, then (with `includeInherited`)
    /// every sequence-scoped attachment filed on any lesson in its sequence and
    /// every area-scoped one filed on any lesson in its area, its own included.
    /// A shared attachment is held by the one lesson it was added to; the
    /// others read it from there (they used to read only their own, so a
    /// "whole sequence" file never showed anywhere else). Most recent first.
    static func getAttachments(forLesson lesson: CDLesson, includeInherited: Bool = true) -> [CDLessonAttachment] {
        let own = ((lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? []).filter { !$0.isDeleted }
        var result = own.filter { $0.scope == .lesson }
        if includeInherited {
            result.append(contentsOf: sharedAttachments(for: lesson, fallback: own))
        }
        return result.sorted { ($0.attachedAt ?? .distantPast) > ($1.attachedAt ?? .distantPast) }
    }

    /// Whether two lessons are filed in the same area (trimmed, any case).
    static func sameArea(_ lhs: CDLesson, _ rhs: CDLesson) -> Bool {
        lhs.area.trimmed().caseInsensitiveCompare(rhs.area.trimmed()) == .orderedSame
    }

    /// Whether two lessons are filed in the same area and sequence.
    static func sameSequence(_ lhs: CDLesson, _ rhs: CDLesson) -> Bool {
        sameArea(lhs, rhs) && lhs.sequence.trimmed().caseInsensitiveCompare(rhs.sequence.trimmed()) == .orderedSame
    }

    /// Sequence- and area-scoped attachments that reach `lesson`, from whichever
    /// lesson holds them. `fallback` (the lesson's own) is used when the lesson
    /// has no context to fetch from.
    private static func sharedAttachments(
        for lesson: CDLesson, fallback: [CDLessonAttachment]
    ) -> [CDLessonAttachment] {
        guard let context = lesson.managedObjectContext else {
            return fallback.filter { $0.scope != .lesson }
        }
        let request = CDFetchRequest(CDLessonAttachment.self)
        request.predicate = NSPredicate(
            format: "scopeRaw IN %@", [AttachmentScope.sequence.rawValue, AttachmentScope.area.rawValue]
        )
        request.relationshipKeyPathsForPrefetching = ["lesson"]
        var seen = Set<NSManagedObjectID>()
        let reaching = context.safeFetch(request).filter { attachment in
            guard !attachment.isDeleted, let holder = attachment.lesson, !holder.isDeleted else { return false }
            switch attachment.scope {
            case .lesson: return false
            case .sequence: return sameSequence(holder, lesson)
            case .area: return sameArea(holder, lesson)
            }
        }
        // Sequence-wide first, then area-wide, as the section lists them.
        return (reaching.filter { $0.scope == .sequence } + reaching.filter { $0.scope == .area })
            .filter { seen.insert($0.objectID).inserted }
    }

    // MARK: - Attachment Import

    /// Imports an attachment file for a lesson with the specified scope.
    /// The file is stored in the organizational directory structure (Area/Sequence/).
    /// - Parameters:
    ///   - sourceURL: The source file URL to import
    ///   - lesson: The lesson to attach the file to
    ///   - scope: The scope of the attachment (lesson, sequence, or area)
    ///   - customName: Optional custom name (a stem, without the extension) for
    ///     the file on disk; if nil, uses the source filename's stem. Either is
    ///     sanitized here, and a name already on disk or held by a record gets
    ///     a number, so the copy never lands on an existing file.
    ///   - storage: The Lesson Files folder unless a test passes its own.
    /// - Returns: A tuple containing the destination URL and relative path
    static func importAttachment(
        from sourceURL: URL,
        forLesson lesson: CDLesson,
        scope: AttachmentScope = .lesson,
        customName: String? = nil,
        in storage: ManagedPDFFileStorage = LessonFileStorage.storage
    ) throws -> (url: URL, relativePath: String) {
        logger.debug("Starting importAttachment for: \(sourceURL.lastPathComponent)")
        logger.debug("CDLesson: \(lesson.name), Scope: \(scope.rawValue)")

        let destDir = try organizationalDirectory(forLesson: lesson, in: storage)
        logger.debug("Destination directory: \(destDir.path)")

        let destinationURL = uniqueAttachmentURL(
            in: destDir,
            scope: scope,
            name: attachmentName(for: sourceURL, customName: customName),
            excluding: nil,
            held: namesHeldByRecords(
                in: destDir, context: lesson.managedObjectContext, apartFrom: nil, storage: storage
            )
        )
        try UbiquitousFile.coordinatedCopy(from: sourceURL, to: destinationURL)

        let relativePath = try storage.relativePath(forManagedURL: destinationURL)
        return (url: destinationURL, relativePath: relativePath)
    }

    /// Imports the new file for a replace of `attachment`: into its lesson's
    /// folder under `title` (a stem), as `importAttachment` would, but
    /// numbered past the attachment's current file ("Foo-3.pdf" after
    /// "Foo-2.pdf", "Foo-2.pdf" after "Foo.pdf"). A replace sends the old file
    /// to the Trash, so starting from the bare name again would put the next
    /// copy under the name iCloud has just deleted, and names would flip
    /// Foo ↔ Foo-2. Counting on gives each copy a name this attachment never
    /// had (`UbiquitousFile`: written once under a new name, never rewritten).
    static func importReplacement(
        from sourceURL: URL,
        for attachment: CDLessonAttachment,
        title: String,
        in storage: ManagedPDFFileStorage = LessonFileStorage.storage
    ) throws -> (url: URL, relativePath: String) {
        guard let lesson = attachment.lesson else { throw CocoaError(.fileNoSuchFile) }
        let destDir = try organizationalDirectory(forLesson: lesson, in: storage)
        let name = attachmentName(for: sourceURL, customName: title)
        let destinationURL = uniqueAttachmentURL(
            in: destDir,
            scope: attachment.scope,
            name: name,
            excluding: nil,
            held: namesHeldByRecords(
                in: destDir, context: attachment.managedObjectContext, apartFrom: nil, storage: storage
            ),
            firstNumber: numberAfter(attachment, named: name)
        )
        try UbiquitousFile.coordinatedCopy(from: sourceURL, to: destinationURL)

        let relativePath = try storage.relativePath(forManagedURL: destinationURL)
        return (url: destinationURL, relativePath: relativePath)
    }

    /// Renames a managed attachment file and returns updated file metadata:
    /// the file's sanitized new name on disk, and the name as typed for the
    /// record (`RenameAttachmentResult.fileName`).
    static func renameAttachment(
        _ attachment: CDLessonAttachment,
        to requestedFileName: String,
        in storage: ManagedPDFFileStorage = LessonFileStorage.storage
    ) throws -> RenameAttachmentResult {
        let trimmedFileName = requestedFileName.trimmed()
        guard !trimmedFileName.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        guard let lesson = attachment.lesson else {
            throw CocoaError(.fileNoSuchFile)
        }

        let currentURL = try storage.resolve(relativePath: attachment.fileRelativePath)
        let requestedURL = URL(fileURLWithPath: trimmedFileName)
        let requestedExtension = requestedURL.pathExtension
        let currentExtension = currentURL.pathExtension
        let resolvedExtension = requestedExtension.isEmpty ? currentExtension : requestedExtension
        let extWithDot = resolvedExtension.isEmpty ? "" : ".\(resolvedExtension)"
        let requestedStem = requestedURL.deletingPathExtension().lastPathComponent
        let sanitizedBaseName = ManagedPDFFileStorage.sanitizeFilenameComponent(
            requestedStem,
            fallback: currentURL.deletingPathExtension().lastPathComponent
        )
        // The record keeps the name as typed ("Area of a Circle — remade");
        // only the file on disk is sanitized.
        let displayFileName = requestedExtension.isEmpty ? trimmedFileName + extWithDot : trimmedFileName

        let destinationDirectory = try organizationalDirectory(forLesson: lesson, in: storage)
        let destinationURL = uniqueAttachmentURL(
            in: destinationDirectory,
            scope: attachment.scope,
            name: AttachmentName(base: sanitizedBaseName, extWithDot: extWithDot),
            excluding: currentURL,
            held: namesHeldByRecords(
                in: destinationDirectory, context: attachment.managedObjectContext, apartFrom: attachment,
                storage: storage
            )
        )

        if currentURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try UbiquitousFile.coordinatedMove(from: currentURL, to: destinationURL)
        }

        let relativePath = try storage.relativePath(forManagedURL: destinationURL)
        return RenameAttachmentResult(
            url: destinationURL,
            relativePath: relativePath,
            fileName: displayFileName,
            fileType: resolvedExtension.lowercased()
        )
    }
}
