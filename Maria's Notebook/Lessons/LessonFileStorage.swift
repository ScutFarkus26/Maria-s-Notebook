import Foundation

public enum LessonFileStorage {
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
            
            print("📱 Using iCloud container path: \(lessonFilesURL.path)")
            print("👁️ This should appear in Finder as: iCloud Drive/Maria's Notebook/Lesson Files")
            try createDirectoryIfNeeded(at: lessonFilesURL)
            return lessonFilesURL
        }

        // Fallback to local Documents directory
        print("⚠️ iCloud not available, using local Documents")
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
    /// The destination filename is constructed from a sanitized lesson name, the lesson UUID suffix, and the source file extension.
    /// Uniqueness is ensured by appending a counter if needed.
    /// Returns the final destination URL.
    public static func importFile(from sourceURL: URL, forLessonWithID lessonID: UUID, lessonName: String?) throws -> URL {
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
        let rel = url.standardizedFileURL.path.replacingOccurrences(of: base.standardizedFileURL.path + "/", with: "")
        return rel
    }

    /// Resolves a relative path (previously returned by `relativePath(forManagedURL:)`) to an absolute URL inside the managed directory.
    public static func resolve(relativePath: String) throws -> URL {
        let base = try lessonFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }
    
    // MARK: - Organizational Structure
    
    /// Returns the organizational path for a lesson: Subject/Group
    /// Creates the directory structure if it doesn't exist.
    static func organizationalDirectory(forLesson lesson: Lesson) throws -> URL {
        print("🗂️ Getting lesson files directory...")
        let baseDir = try lessonFilesDirectory()
        print("✅ Base directory: \(baseDir.path)")
        
        // Sanitize subject and group names for filesystem
        let sanitizedSubject = sanitizeFilenameComponent(lesson.subject, fallback: "General")
        let sanitizedGroup = sanitizeFilenameComponent(lesson.group, fallback: "Ungrouped")
        print("📁 Sanitized subject: '\(sanitizedSubject)', group: '\(sanitizedGroup)'")
        
        // Create Subject/Group structure
        let orgDir = baseDir
            .appendingPathComponent(sanitizedSubject, isDirectory: true)
            .appendingPathComponent(sanitizedGroup, isDirectory: true)
        
        print("📂 Creating directory at: \(orgDir.path)")
        try createDirectoryIfNeeded(at: orgDir)
        print("✅ Directory created/exists")
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
        print("📥 Starting importAttachment for: \(sourceURL.lastPathComponent)")
        print("📌 Lesson: \(lesson.name), Scope: \(scope.rawValue)")
        
        let fm = FileManager.default
        
        // Get the organizational directory for this lesson
        let destDir = try organizationalDirectory(forLesson: lesson)
        print("📂 Destination directory: \(destDir.path)")
        
        // Extract file extension
        let sourceExt = sourceURL.pathExtension
        let extWithDot = sourceExt.isEmpty ? "" : "." + sourceExt
        
        // Determine base filename
        let baseName: String
        if let customName = customName {
            baseName = sanitizeFilenameComponent(customName, fallback: sourceURL.deletingPathExtension().lastPathComponent)
        } else {
            baseName = sanitizeFilenameComponent(sourceURL.deletingPathExtension().lastPathComponent, fallback: "Attachment")
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

    /// Sanitizes a filename component by allowing only alphanumerics, space, dash, underscore, and dot.
    /// Other characters replaced with dash. Repeated dashes are collapsed.
    /// Leading/trailing dots and spaces are trimmed.
    /// Ensures the result is not empty; if so returns fallback.
    private static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
        guard let input = input, !input.isEmpty else {
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
    
    // MARK: - Migration
    
    /// Migrates files from the old private iCloud container location to the new public iCloud Drive location.
    /// This should be called once during app startup to move existing files to the user-visible location.
    /// - Returns: Number of files migrated, or nil if no migration was needed
    @discardableResult
    public static func migrateToICloudDrive() -> Int? {
        let fm = FileManager.default
        
        // Get the old location (private container - iCloud~AppID~/Documents/Lesson Files/)
        guard let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) else {
            print("⚠️ No iCloud container available for migration")
            return nil
        }
        
        let oldLocation = ubiquityURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Lesson Files", isDirectory: true)
        
        // Check if old location exists and has files
        guard fm.fileExists(atPath: oldLocation.path) else {
            print("ℹ️ No old files to migrate")
            return nil
        }
        
        do {
            // Get the new location (public iCloud Drive)
            let newLocation = try lessonFilesDirectory()
            
            // Check if they're the same (migration already done or not needed)
            if oldLocation.standardizedFileURL == newLocation.standardizedFileURL {
                print("ℹ️ Already using new location, no migration needed")
                return nil
            }
            
            print("🔄 Starting migration from:")
            print("   Old: \(oldLocation.path)")
            print("   New: \(newLocation.path)")
            
            // Get all items in old location (recursively to handle Subject/Group folders)
            let contents = try fm.contentsOfDirectory(at: oldLocation, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            var migratedCount = 0
            
            for oldItemURL in contents {
                let itemName = oldItemURL.lastPathComponent
                let newItemURL = newLocation.appendingPathComponent(itemName)
                
                // Skip .DS_Store files
                if itemName == ".DS_Store" {
                    continue
                }
                
                // Check if it's a directory or file
                let resourceValues = try oldItemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false
                
                if isDirectory {
                    // Recursively migrate directory contents
                    if !fm.fileExists(atPath: newItemURL.path) {
                        try fm.createDirectory(at: newItemURL, withIntermediateDirectories: true)
                    }
                    
                    let subContents = try fm.contentsOfDirectory(at: oldItemURL, includingPropertiesForKeys: nil)
                    for subItemURL in subContents {
                        let subItemName = subItemURL.lastPathComponent
                        if subItemName == ".DS_Store" { continue }
                        
                        let newSubItemURL = newItemURL.appendingPathComponent(subItemName)
                        if !fm.fileExists(atPath: newSubItemURL.path) {
                            try fm.moveItem(at: subItemURL, to: newSubItemURL)
                            print("✅ Migrated: \(itemName)/\(subItemName)")
                            migratedCount += 1
                        }
                    }
                } else {
                    // Move file
                    if !fm.fileExists(atPath: newItemURL.path) {
                        try fm.moveItem(at: oldItemURL, to: newItemURL)
                        print("✅ Migrated: \(itemName)")
                        migratedCount += 1
                    } else {
                        print("⏭️ Skipping \(itemName) - already exists at destination")
                    }
                }
            }
            
            // Clean up empty directories in old location
            let remainingContents = try fm.contentsOfDirectory(at: oldLocation, includingPropertiesForKeys: nil)
            let nonDSStoreContents = remainingContents.filter { $0.lastPathComponent != ".DS_Store" }
            if nonDSStoreContents.isEmpty {
                do {
                    try fm.removeItem(at: oldLocation)
                    print("🗑️ Removed empty old location")
                } catch {
                    print("⚠️ [migrateToICloudDrive] Failed to remove old location: \(error)")
                }
            }
            
            print("✅ Migration complete: \(migratedCount) files migrated")
            return migratedCount
            
        } catch {
            print("❌ Migration failed: \(error)")
            return nil
        }
    }
}
