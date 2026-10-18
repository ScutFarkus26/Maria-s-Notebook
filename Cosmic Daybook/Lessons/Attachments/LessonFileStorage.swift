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

        let destinationURL = uniqueAttachmentURL(
            in: destDir,
            scope: scope,
            name: AttachmentName(base: baseName, extWithDot: extWithDot),
            excluding: nil,
            held: namesHeldByRecords(in: destDir, context: lesson.managedObjectContext, apartFrom: nil)
        )
        try UbiquitousFile.coordinatedCopy(from: sourceURL, to: destinationURL)

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
            excluding: currentURL,
            held: namesHeldByRecords(
                in: destinationDirectory, context: attachment.managedObjectContext, apartFrom: attachment
            )
        )

        if currentURL.standardizedFileURL != destinationURL.standardizedFileURL {
            try UbiquitousFile.coordinatedMove(from: currentURL, to: destinationURL)
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
    /// current URL counts as free so a rename to the same name is a no-op. A
    /// name held by a file still in iCloud (not downloaded here yet) is taken,
    /// as it is there, and so is one in `held`: an attachment record synced
    /// from another device whose file hasn't reached this one at all.
    private static func uniqueAttachmentURL(
        in directory: URL,
        scope: AttachmentScope,
        name: AttachmentName,
        excluding currentURL: URL?,
        held: Set<String>
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
            if let currentURL, candidate.standardizedFileURL == currentURL.standardizedFileURL {
                return candidate
            }
            let taken = fm.fileExists(atPath: candidate.path)
                || fm.fileExists(atPath: UbiquitousFile.placeholderURL(for: candidate).path)
                || held.contains(candidate.lastPathComponent.lowercased())
            if !taken {
                return candidate
            }

            counter = (counter ?? 1) + 1
        }
    }

    /// The file names (lowercased: iCloud Drive ignores case) that attachment
    /// records in `context` hold directly inside `directory`, `apartFrom`'s
    /// own aside. A record synced from another device can arrive before its
    /// file does, and a second file under its name would collide with that
    /// one when it lands.
    private static func namesHeldByRecords(
        in directory: URL,
        context: NSManagedObjectContext?,
        apartFrom attachment: CDLessonAttachment?
    ) -> Set<String> {
        guard let context, let folder = try? relativePath(forManagedURL: directory) else { return [] }
        let prefix = folder.lowercased() + "/"
        let request = CDFetchRequest(CDLessonAttachment.self)
        request.predicate = NSPredicate(format: "fileRelativePath BEGINSWITH[c] %@", prefix)
        var held = Set<String>()
        for record in context.safeFetch(request) where record !== attachment && !record.isDeleted {
            let path = record.fileRelativePath.lowercased()
            guard path.hasPrefix(prefix) else { continue }
            let name = path.dropFirst(prefix.count)
            if !name.isEmpty, !name.contains("/") {
                held.insert(String(name))
            }
        }
        return held
    }
}
