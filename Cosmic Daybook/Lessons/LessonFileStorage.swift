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
        let fileName: String
        let fileType: String
    }

    private struct AttachmentName {
        let base: String
        let extWithDot: String
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
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
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
    /// Creates the directory structure if it doesn't exist.
    static func organizationalDirectory(forLesson lesson: CDLesson) throws -> URL {
        logger.debug("Getting lesson files directory...")
        let baseDir = try lessonFilesDirectory()
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

    /// Returns all attachments for a lesson, including inherited ones from sequence and area scope.
    /// - Parameter lesson: The lesson to get attachments for
    /// - Parameter includeInherited: Whether to include sequence and area-scoped attachments
    /// - Returns: Array of attachments, with lesson-specific first, then sequence, then area
    static func getAttachments(forLesson lesson: CDLesson, includeInherited: Bool = true) -> [CDLessonAttachment] {
        let allLessonAttachments = (lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? []

        // Always include lesson-specific attachments
        var result = allLessonAttachments.filter { $0.scope == .lesson }

        if includeInherited {
            // Add sequence-scoped attachments
            result.append(contentsOf: allLessonAttachments.filter { $0.scope == .sequence })

            // Add area-scoped attachments
            result.append(contentsOf: allLessonAttachments.filter { $0.scope == .area })
        }

        // Sort by attachment date, most recent first
        return result.sorted { ($0.attachedAt ?? .distantPast) > ($1.attachedAt ?? .distantPast) }
    }

    // MARK: - Attachment Import

    /// Imports an attachment file for a lesson with the specified scope.
    /// The file is stored in the organizational directory structure (Area/Sequence/).
    /// - Parameters:
    ///   - sourceURL: The source file URL to import
    ///   - lesson: The lesson to attach the file to
    ///   - scope: The scope of the attachment (lesson, sequence, or area)
    ///   - customName: Optional custom name for the attachment (if nil, uses source filename)
    /// - Returns: A tuple containing the destination URL and relative path
    static func importAttachment(
        from sourceURL: URL,
        forLesson lesson: CDLesson,
        scope: AttachmentScope = .lesson,
        customName: String? = nil
    ) throws -> (url: URL, relativePath: String) {
        logger.debug("Starting importAttachment for: \(sourceURL.lastPathComponent)")
        logger.debug("CDLesson: \(lesson.name), Scope: \(scope.rawValue)")

        let destDir = try organizationalDirectory(forLesson: lesson)
        logger.debug("Destination directory: \(destDir.path)")

        let sourceExt = sourceURL.pathExtension
        let extWithDot = sourceExt.isEmpty ? "" : "." + sourceExt

        let baseName: String
        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent
        if let customName {
            baseName = ManagedPDFFileStorage.sanitizeFilenameComponent(customName, fallback: sourceStem)
        } else {
            baseName = ManagedPDFFileStorage.sanitizeFilenameComponent(sourceStem, fallback: "Attachment")
        }

        let destinationURL = storage.uniqueDestination(
            in: destDir,
            baseName: scopePrefix(for: scope) + baseName,
            extWithDot: extWithDot
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let relativePath = try self.relativePath(forManagedURL: destinationURL)
        return (url: destinationURL, relativePath: relativePath)
    }

    /// Renames a managed attachment file and returns updated file metadata.
    static func renameAttachment(
        _ attachment: CDLessonAttachment,
        to requestedFileName: String
    ) throws -> RenameAttachmentResult {
        let trimmedFileName = requestedFileName.trimmed()
        guard !trimmedFileName.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        guard let lesson = attachment.lesson else {
            throw CocoaError(.fileNoSuchFile)
        }

        let currentURL = try resolve(relativePath: attachment.fileRelativePath)
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
        let displayFileName = sanitizedBaseName + extWithDot

        let destinationDirectory = try organizationalDirectory(forLesson: lesson)
        let destinationURL = uniqueAttachmentURL(
            in: destinationDirectory,
            scope: attachment.scope,
            name: AttachmentName(base: sanitizedBaseName, extWithDot: extWithDot),
            excluding: currentURL
        )

        let fm = FileManager.default
        if currentURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try fm.moveItem(at: currentURL, to: destinationURL)
        }

        let relativePath = try relativePath(forManagedURL: destinationURL)
        return RenameAttachmentResult(
            url: destinationURL,
            relativePath: relativePath,
            fileName: displayFileName,
            fileType: resolvedExtension.lowercased()
        )
    }

    // MARK: - Private Helpers

    private static func scopePrefix(for scope: AttachmentScope) -> String {
        switch scope {
        case .lesson: return ""
        case .sequence: return "[Sequence] "
        case .area: return "[Area] "
        }
    }

    /// Like `ManagedPDFFileStorage.uniqueDestination`, except the attachment's own
    /// current URL counts as free so a rename to the same name is a no-op.
    private static func uniqueAttachmentURL(
        in directory: URL,
        scope: AttachmentScope,
        name: AttachmentName,
        excluding currentURL: URL
    ) -> URL {
        let fm = FileManager.default
        let scopePrefix = scopePrefix(for: scope)

        func candidateURL(counter: Int?) -> URL {
            let filename: String
            if let counter {
                filename = "\(scopePrefix)\(name.base)-\(counter)\(name.extWithDot)"
            } else {
                filename = "\(scopePrefix)\(name.base)\(name.extWithDot)"
            }
            return directory.appendingPathComponent(filename, isDirectory: false)
        }

        var counter: Int?
        while true {
            let candidate = candidateURL(counter: counter)
            if candidate.standardizedFileURL == currentURL.standardizedFileURL
                || !fm.fileExists(atPath: candidate.path) {
                return candidate
            }

            counter = (counter ?? 1) + 1
        }
    }
}
