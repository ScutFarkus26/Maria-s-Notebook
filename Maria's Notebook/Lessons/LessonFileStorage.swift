// swiftlint:disable file_length
import Foundation
import OSLog

// swiftlint:disable type_body_length
public enum LessonFileStorage {
    static let logger = Logger.lessons

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
    /// Returns the root directory URL where lesson files are stored.
    /// Uses the app's iCloud container Documents folder (visible in Finder as "Maria's Notebook") if available,
    /// otherwise falls back to the app's local Documents directory.
    /// Ensures the directory exists before returning.
    public static func lessonFilesDirectory() throws -> URL {
        let fm = FileManager.default

        // Use the app's iCloud container - this will appear in Finder's iCloud Drive
        // The CloudDocuments entitlement makes the container visible in Finder
        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let lessonFilesURL = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Lesson Files", isDirectory: true)
            
            logger.debug("Using iCloud container path: \(lessonFilesURL.path)")
            logger.debug("Visible in Finder as: iCloud Drive/Maria's Notebook/Lesson Files")
            try createDirectoryIfNeeded(at: lessonFilesURL)
            return lessonFilesURL
        }

        // Fallback to local Documents directory
        logger.warning("iCloud not available, using local Documents")
        let documentsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lesson Files", isDirectory: true)
        try createDirectoryIfNeeded(at: documentsURL)
        return documentsURL
    }

    /// Returns true if the given URL is inside the managed lesson files directory.
    public static func isManagedURL(_ url: URL) -> Bool {
        do {
            let managedDir = try lessonFilesDirectory().standardizedFileURL
            let standardizedURL = url.standardizedFileURL

            let managedPath = managedDir.path + "/"
            let urlPath = standardizedURL.path

            return urlPath.hasPrefix(managedPath)
        } catch {
            return false
        }
    }

    /// Deletes the item at the given URL if it is inside the managed lesson files directory.
    /// Does nothing if the URL is not managed or does not exist.
    public static func deleteIfManaged(_ url: URL) throws {
        let fm = FileManager.default
        guard isManagedURL(url) else { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Imports a file or package directory from a source URL into the managed lesson files directory.
    /// The destination filename is constructed from a sanitized lesson name,
    /// the lesson UUID suffix, and the source file extension.
    /// Uniqueness is ensured by appending a counter if needed.
    /// Returns the final destination URL.
    public static func importFile(
        from sourceURL: URL,
        forLessonWithID lessonID: UUID,
        lessonName: String?
    ) throws -> URL {
        let fm = FileManager.default

        let destDir = try lessonFilesDirectory()

        try createDirectoryIfNeeded(at: destDir)

        // Extract file extension (including dot), if any
        let sourceExt = sourceURL.pathExtension
        let extWithDot: String
        if !sourceExt.isEmpty {
            extWithDot = "." + sourceExt
        } else {
            extWithDot = ""
        }

        // Sanitize lesson name or fallback
        let baseNameSanitized = sanitizeFilenameComponent(lessonName?.trimmed(), fallback: "Lesson")

        // UUID suffix: last 8 characters of UUID string without hyphens
        let uuidString = lessonID.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidSuffix = String(uuidString.suffix(8))

        var baseFilename = "\(baseNameSanitized)-\(uuidSuffix)"
        if !extWithDot.isEmpty {
            baseFilename += extWithDot
        }

        var destinationURL = destDir.appendingPathComponent(baseFilename, isDirectory: false)

        // Ensure uniqueness by appending a counter
        var counter = 1
        while fm.fileExists(atPath: destinationURL.path) {
            let numberedBase = "\(baseNameSanitized)-\(uuidSuffix)-\(counter)"
            let filename = numberedBase + extWithDot
            destinationURL = destDir.appendingPathComponent(filename, isDirectory: false)
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    /// Creates a standard bookmark Data for the given URL without security scope.
    public static func makeBookmark(for url: URL) throws -> Data {
        let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return bookmarkData
    }

    /// Returns a relative path string for a managed URL, relative to the lesson files directory.
    public static func relativePath(forManagedURL url: URL) throws -> String {
        let base = try lessonFilesDirectory()
        let basePath = base.standardizedFileURL.path + "/"
        let rel = url.standardizedFileURL.path
            .replacingOccurrences(of: basePath, with: "")
        return rel
    }

    /// Resolves a relative path (previously returned by `relativePath(forManagedURL:)`)
    /// to an absolute URL inside the managed directory.
    public static func resolve(relativePath: String) throws -> URL {
        let base = try lessonFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }
    
    // MARK: - Organizational Structure
    
    /// Returns the organizational path for a lesson: Subject/Group
    /// Creates the directory structure if it doesn't exist.
    static func organizationalDirectory(forLesson lesson: Lesson) throws -> URL {
        logger.debug("Getting lesson files directory...")
        let baseDir = try lessonFilesDirectory()
        logger.debug("Base directory: \(baseDir.path)")
        
        // Sanitize subject and group names for filesystem
        let sanitizedSubject = sanitizeFilenameComponent(lesson.subject, fallback: "General")
        let sanitizedGroup = sanitizeFilenameComponent(lesson.group, fallback: "Ungrouped")
        logger.debug("Sanitized subject: '\(sanitizedSubject)', group: '\(sanitizedGroup)'")
        
        // Create Subject/Group structure
        let orgDir = baseDir
            .appendingPathComponent(sanitizedSubject, isDirectory: true)
            .appendingPathComponent(sanitizedGroup, isDirectory: true)
        
        logger.debug("Creating directory at: \(orgDir.path)")
        try createDirectoryIfNeeded(at: orgDir)
        logger.debug("Directory created/exists")
        return orgDir
    }
    
    /// Returns all attachments for a lesson, including inherited ones from group and subject scope.
    /// - Parameter lesson: The lesson to get attachments for
    /// - Parameter includeInherited: Whether to include group and subject-scoped attachments
    /// - Returns: Array of attachments, with lesson-specific first, then group, then subject
    static func getAttachments(forLesson lesson: Lesson, includeInherited: Bool = true) -> [LessonAttachment] {
        guard let allLessonAttachments = lesson.attachments else { return [] }
        
        // Always include lesson-specific attachments
        var result = allLessonAttachments.filter { $0.scope == .lesson }
        
        if includeInherited {
            // Add group-scoped attachments
            result.append(contentsOf: allLessonAttachments.filter { $0.scope == .group })
            
            // Add subject-scoped attachments
            result.append(contentsOf: allLessonAttachments.filter { $0.scope == .subject })
        }
        
        // Sort by attachment date, most recent first
        return result.sorted { $0.attachedAt > $1.attachedAt }
    }
    
    // MARK: - Attachment Import
    
    /// Imports an attachment file for a lesson with the specified scope.
    /// The file is stored in the organizational directory structure (Subject/Group/).
    /// - Parameters:
    ///   - sourceURL: The source file URL to import
    ///   - lesson: The lesson to attach the file to
    ///   - scope: The scope of the attachment (lesson, group, or subject)
    ///   - customName: Optional custom name for the attachment (if nil, uses source filename)
    /// - Returns: A tuple containing the destination URL and relative path
    static func importAttachment(
        from sourceURL: URL,
        forLesson lesson: Lesson,
        scope: AttachmentScope = .lesson,
        customName: String? = nil
    ) throws -> (url: URL, relativePath: String) {
        logger.debug("Starting importAttachment for: \(sourceURL.lastPathComponent)")
        logger.debug("Lesson: \(lesson.name), Scope: \(scope.rawValue)")
        
        let fm = FileManager.default
        
        // Get the organizational directory for this lesson
        let destDir = try organizationalDirectory(forLesson: lesson)
        logger.debug("Destination directory: \(destDir.path)")
        
        // Extract file extension
        let sourceExt = sourceURL.pathExtension
        let extWithDot = sourceExt.isEmpty ? "" : "." + sourceExt
        
        // Determine base filename
        let baseName: String
        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent
        if let customName {
            baseName = sanitizeFilenameComponent(customName, fallback: sourceStem)
        } else {
            baseName = sanitizeFilenameComponent(sourceStem, fallback: "Attachment")
        }
        
        // Add scope prefix for non-lesson attachments
        let scopePrefix: String
        switch scope {
        case .lesson:
            scopePrefix = ""
        case .group:
            scopePrefix = "[Group] "
        case .subject:
            scopePrefix = "[Subject] "
        }
        
        // Add lesson UUID suffix for lesson-scoped attachments to ensure uniqueness
        let uuidString = lesson.id.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidSuffix = String(uuidString.suffix(8))
        
        let baseFilename = scope == .lesson
            ? "\(baseName)-\(uuidSuffix)\(extWithDot)"
            : "\(scopePrefix)\(baseName)\(extWithDot)"
        
        var destinationURL = destDir.appendingPathComponent(baseFilename, isDirectory: false)
        
        // Ensure uniqueness by appending a counter
        var counter = 1
        while fm.fileExists(atPath: destinationURL.path) {
            let numberedFilename = scope == .lesson
                ? "\(baseName)-\(uuidSuffix)-\(counter)\(extWithDot)"
                : "\(scopePrefix)\(baseName)-\(counter)\(extWithDot)"
            destinationURL = destDir.appendingPathComponent(numberedFilename, isDirectory: false)
            counter += 1
        }
        
        // Copy the file
        try fm.copyItem(at: sourceURL, to: destinationURL)
        
        // Get relative path
        let relativePath = try self.relativePath(forManagedURL: destinationURL)
        
        return (url: destinationURL, relativePath: relativePath)
    }

    /// Renames a managed attachment file and returns updated file metadata.
    static func renameAttachment(
        _ attachment: LessonAttachment,
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
        let sanitizedBaseName = sanitizeFilenameComponent(
            requestedStem,
            fallback: currentURL.deletingPathExtension().lastPathComponent
        )
        let displayFileName = sanitizedBaseName + extWithDot

        let destinationDirectory = try organizationalDirectory(forLesson: lesson)
        let destinationURL = try uniqueAttachmentURL(
            in: destinationDirectory,
            lesson: lesson,
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
    
    /// Searches for attachments matching a keyword across subjects, groups, or specific lessons.
    /// - Parameters:
    ///   - keyword: Search term to match against filenames and notes
    ///   - subject: Optional subject filter
    ///   - group: Optional group filter (requires subject to be set)
    /// - Returns: Array of matching attachments
    static func searchAttachments(
        keyword: String,
        subject: String? = nil,
        group: String? = nil
    ) throws -> [LessonAttachment] {
        // This is a placeholder for future implementation
        // Would require access to ModelContext to query all attachments
        // For now, return empty array
        return []
    }

    // MARK: - Private Helpers

    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                // Exists but is not a directory, remove it and create directory
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private static func uniqueAttachmentURL(
        in directory: URL,
        lesson: Lesson,
        scope: AttachmentScope,
        name: AttachmentName,
        excluding currentURL: URL
    ) throws -> URL {
        let fm = FileManager.default

        let scopePrefix: String
        switch scope {
        case .lesson:
            scopePrefix = ""
        case .group:
            scopePrefix = "[Group] "
        case .subject:
            scopePrefix = "[Subject] "
        }

        let uuidString = lesson.id.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidSuffix = String(uuidString.suffix(8))

        func candidateURL(counter: Int?) -> URL {
            let filename: String
            switch scope {
            case .lesson:
                if let counter {
                    filename = "\(name.base)-\(uuidSuffix)-\(counter)\(name.extWithDot)"
                } else {
                    filename = "\(name.base)-\(uuidSuffix)\(name.extWithDot)"
                }
            case .group, .subject:
                if let counter {
                    filename = "\(scopePrefix)\(name.base)-\(counter)\(name.extWithDot)"
                } else {
                    filename = "\(scopePrefix)\(name.base)\(name.extWithDot)"
                }
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

            counter = (counter ?? 0) + 1
        }
    }

    /// Sanitizes a filename component by allowing only alphanumerics, space, dash, underscore, and dot.
    /// Other characters replaced with dash. Repeated dashes are collapsed.
    /// Leading/trailing dots and spaces are trimmed.
    /// Ensures the result is not empty; if so returns fallback.
    private static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
        guard let input, !input.isEmpty else {
            return fallback
        }

        // Allowed characters: alphanumeric, space, dash, underscore, dot
        // Replace disallowed characters with dash
        let allowedCharacterSet = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_." 
        )

        // Replace disallowed characters with dash
        var sanitized = input.unicodeScalars.map { scalar -> Character in
            if allowedCharacterSet.contains(scalar) {
                return Character(scalar)
            } else {
                return "-"
            }
        }.reduce(into: "") { $0.append($1) }

        // Collapse repeated dashes
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing dots and spaces and dashes
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

        if sanitized.isEmpty {
            return fallback
        }

        return sanitized
    }
}
// swiftlint:enable type_body_length
