import Foundation
import CoreData
import OSLog

/// One-time migration that:
/// 1. Moves any files stranded in `Documents/CDLesson Files/` and `Documents/CDResource Files/`
///    (introduced by the SwiftData→Core Data refactor on 2026-03-31) back to their original
///    visible folder names: `Lesson Files/` and `Resource Files/`.
/// 2. Migrates `CDDocument.pdfData` blobs into per-student PDF files under
///    `Documents/Student Files/{Student Name}/`.
///
/// Idempotent: safe to re-run. Gated by `UserDefaultsKeys.pdfFolderMigrationV1Complete`.
enum PDFFolderMigrationService {
    private static let logger = Logger.migration

    private static let strandedFolderRenames: [(old: String, new: String)] = [
        ("CDLesson Files", "Lesson Files"),
        ("CDResource Files", "Resource Files")
    ]

    /// Runs the migration if it hasn't already completed. Safe to call from a background task.
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UserDefaultsKeys.pdfFolderMigrationV1Complete) {
            return
        }

        logger.info("PDF folder migration: starting")
        let start = Date()

        let folderRenameSucceeded = renameStrandedFolders()

        let context = await MainActor.run { coreDataStack.viewContext }
        let documentMigrationSucceeded = await migrateStudentDocuments(using: context)

        if folderRenameSucceeded && documentMigrationSucceeded {
            defaults.set(true, forKey: UserDefaultsKeys.pdfFolderMigrationV1Complete)
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            logger.info("PDF folder migration: complete in \(elapsed)")
        } else {
            logger.warning("PDF folder migration: incomplete; will retry on next launch")
        }
    }

    // MARK: - Folder rename

    private static func renameStrandedFolders() -> Bool {
        guard let documentsRoot = iCloudDocumentsRoot() else {
            logger.warning("PDF folder migration: iCloud unavailable; skipping folder rename")
            return true // not fatal — local-only stores have nothing to rescue
        }

        var allOK = true
        for (oldName, newName) in strandedFolderRenames {
            let oldRoot = documentsRoot.appendingPathComponent(oldName, isDirectory: true)
            let newRoot = documentsRoot.appendingPathComponent(newName, isDirectory: true)

            if !FileManager.default.fileExists(atPath: oldRoot.path) {
                continue
            }

            do {
                try moveContents(from: oldRoot, to: newRoot)
                try removeIfEmpty(oldRoot)
                logger.info("PDF folder migration: rescued stranded files from \(oldName) → \(newName)")
            } catch {
                logger.error("PDF folder migration: failed to migrate \(oldName): \(error.localizedDescription)")
                allOK = false
            }
        }
        return allOK
    }

    private static func iCloudDocumentsRoot() -> URL? {
        guard let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return ubiquity.appendingPathComponent("Documents", isDirectory: true)
    }

    private static func moveContents(from oldRoot: URL, to newRoot: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)

        let oldRootStandardized = oldRoot.standardizedFileURL.path + "/"
        guard let enumerator = fm.enumerator(at: oldRoot, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return
        }

        for case let fileURL as URL in enumerator {
            try moveSingleFile(fileURL: fileURL, oldRootPath: oldRootStandardized, newRoot: newRoot)
        }
    }

    private static func moveSingleFile(fileURL: URL, oldRootPath: String, newRoot: URL) throws {
        let fm = FileManager.default
        let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues?.isRegularFile == true else { return }

        let standardized = fileURL.standardizedFileURL.path
        guard standardized.hasPrefix(oldRootPath) else { return }
        let relative = String(standardized.dropFirst(oldRootPath.count))
        let destination = newRoot.appendingPathComponent(relative, isDirectory: false)

        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let finalDest = uniqueDestination(for: destination)
        try fm.moveItem(at: fileURL, to: finalDest)
    }

    private static func uniqueDestination(for url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let extWithDot = ext.isEmpty ? "" : ".\(ext)"

        var counter = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem)-\(counter)\(extWithDot)", isDirectory: false)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private static func removeIfEmpty(_ directory: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let contents = try fm.contentsOfDirectory(atPath: directory.path).filter { $0 != ".DS_Store" }
        if contents.isEmpty {
            try? fm.removeItem(at: directory)
        }
    }

    // MARK: - Student document migration

    /// Walks `CDDocument` rows whose `pdfData` is non-nil, writes the bytes to disk under
    /// the student's folder, sets the bookmark + relative path, and clears `pdfData`.
    @MainActor
    private static func migrateStudentDocuments(using context: NSManagedObjectContext) async -> Bool {
        let request = NSFetchRequest<CDDocument>(entityName: "Document")
        request.predicate = NSPredicate(format: "pdfData != nil")
        request.fetchBatchSize = 20

        let documents: [CDDocument]
        do {
            documents = try context.fetch(request)
        } catch {
            logger.error("PDF folder migration: failed to fetch CDDocument rows: \(error.localizedDescription)")
            return false
        }

        if documents.isEmpty { return true }

        logger.info("PDF folder migration: found \(documents.count) student document blobs to migrate")

        var migrated = 0
        var failed = 0
        for (index, document) in documents.enumerated() {
            guard let data = document.pdfData else { continue }

            let studentName = document.student?.fullName
            let title = document.title.trimmed().isEmpty ? "Document" : document.title

            do {
                let imported = try StudentDocumentFileStorage.writePDFData(
                    data,
                    studentName: studentName,
                    title: title
                )
                document.pdfFileBookmark = imported.bookmark
                document.pdfFileRelativePath = imported.relativePath
                document.pdfData = nil
                migrated += 1
            } catch {
                let title = document.title
                let reason = error.localizedDescription
                logger.error("PDF folder migration: failed to migrate \(title): \(reason)")
                failed += 1
            }

            // Save in batches of 10 to bound write amplification on CloudKit
            if index.isMultiple(of: 10) {
                saveContext(context)
            }
        }

        saveContext(context)
        logger.info("PDF folder migration: migrated \(migrated) student documents (\(failed) failed)")
        return failed == 0
    }

    @MainActor
    private static func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("PDF folder migration: save failed: \(error.localizedDescription)")
        }
    }
}
