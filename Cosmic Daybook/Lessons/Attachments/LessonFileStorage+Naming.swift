//
//  LessonFileStorage+Naming.swift
//  Cosmic Daybook
//
//  The names lesson files get on disk: sanitized, scope-prefixed, and
//  numbered so that a copy never lands on a name that is taken, here, in
//  iCloud, or by a record whose file hasn't arrived yet.
//

import CoreData
import Foundation

extension LessonFileStorage {
    /// A name on disk before its scope prefix and number: the sanitized stem
    /// and the extension with its dot ("" for none).
    struct AttachmentName {
        let base: String
        let extWithDot: String
    }

    static func scopePrefix(for scope: AttachmentScope) -> String {
        switch scope {
        case .lesson: return ""
        case .sequence: return "[Sequence] "
        case .area: return "[Area] "
        }
    }

    /// The name a copy of `sourceURL` is filed under: `customName` (a stem)
    /// or else the source's own stem, sanitized, with the source's extension.
    /// A custom name that sanitizes to nothing (all Hebrew, say) falls back
    /// to the source's sanitized stem, never to a raw one.
    static func attachmentName(for sourceURL: URL, customName: String?) -> AttachmentName {
        let sourceExt = sourceURL.pathExtension
        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent
        let sourceBaseName = ManagedPDFFileStorage.sanitizeFilenameComponent(sourceStem, fallback: "Attachment")
        let baseName = customName.map {
            ManagedPDFFileStorage.sanitizeFilenameComponent($0, fallback: sourceBaseName)
        } ?? sourceBaseName
        return AttachmentName(base: baseName, extWithDot: sourceExt.isEmpty ? "" : "." + sourceExt)
    }

    /// The number a replace's copy is first tried with: one past the number
    /// on `attachment`'s current file when that is `name` numbered ("Foo-3"
    /// gives 4), 2 when it is `name` itself, in any case and whatever its
    /// extension; nil, the bare name first, when the file has another name.
    static func numberAfter(_ attachment: CDLessonAttachment, named name: AttachmentName) -> Int? {
        let fileName = (attachment.fileRelativePath as NSString).lastPathComponent
        let current = CDLessonAttachment.titleStem(of: fileName, fileType: attachment.fileType).lowercased()
        let base = (scopePrefix(for: attachment.scope) + name.base).lowercased()
        if current == base { return 2 }
        guard current.hasPrefix(base + "-"),
              let number = Int(current.dropFirst(base.count + 1)), number >= 2 else { return nil }
        return number + 1
    }

    /// Like `ManagedPDFFileStorage.uniqueDestination`, except the attachment's own
    /// current URL counts as free so a rename to the same name is a no-op. A
    /// name held by a file still in iCloud (not downloaded here yet) is taken,
    /// as it is there, and so is one in `held`: an attachment record synced
    /// from another device whose file hasn't reached this one at all.
    /// `firstNumber` starts the count past the bare name ("-<n>" first).
    static func uniqueAttachmentURL(
        in directory: URL,
        scope: AttachmentScope,
        name: AttachmentName,
        excluding currentURL: URL?,
        held: Set<String>,
        firstNumber: Int? = nil
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

        var counter = firstNumber
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
    static func namesHeldByRecords(
        in directory: URL,
        context: NSManagedObjectContext?,
        apartFrom attachment: CDLessonAttachment?,
        storage: ManagedPDFFileStorage
    ) -> Set<String> {
        guard let context, let folder = try? storage.relativePath(forManagedURL: directory) else { return [] }
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
