//
//  LessonAttachmentService+Checks.swift
//  Cosmic Daybook
//
//  What a file must be before it is attached, and the problems a lesson
//  file change can run into, in plain words.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension LessonAttachmentService {
    /// Why a file can't be attached or changed, in words the guide (or
    /// Claude) can act on. The underlying error, if any, is logged.
    nonisolated enum Problem: LocalizedError, Equatable {
        case fileMissing
        case folder
        case notAFile
        /// `allowed` reads "a PDF or an image".
        case wrongType(allowed: String)
        /// `kind` reads "a PDF" or "an image".
        case notReadable(kind: String)
        case tooLarge
        case sampleClass
        case noLesson
        case emptyName
        case saveFailed

        /// Why the Sample Class can't add or change files.
        static let sampleClassMessage = "The Sample Class shares your class's lesson files, "
            + "so it can't add or change them. Switch to My Class to add a file."

        var errorDescription: String? {
            switch self {
            case .fileMissing:
                return "Couldn't find that file. It may have been moved or deleted."
            case .folder:
                return "That's a folder, not a file. Choose a file to attach."
            case .notAFile:
                return "That isn't a file that can be attached. Choose a file to attach."
            case .wrongType(let allowed):
                return "That kind of file can't be attached here. Choose \(allowed)."
            case .notReadable(let kind):
                return "That file is named like \(kind) but can't be read as one. "
                    + "Check that it opens, then try again."
            case .tooLarge:
                return "That file is larger than 50 MB, which is too large to attach. "
                    + "Make it smaller, then try again."
            case .sampleClass:
                return Self.sampleClassMessage
            case .noLesson:
                return "This file isn't on a lesson any more."
            case .emptyName:
                return "Type a name for the file."
            case .saveFailed:
                return "Couldn't save the change. Try again."
            }
        }
    }

    /// A file `validate` accepted: where it really is (symbolic links
    /// followed), what its content type is, and how many bytes it holds.
    nonisolated struct CheckedFile: Sendable, Equatable {
        let url: URL
        let contentType: UTType
        let size: Int64
    }

    // MARK: - Checking a file

    /// Checks a file before it is attached: it exists and is a file (a
    /// package such as a Pages document counts; a folder doesn't), its real
    /// content type (`URLResourceValues.contentType`) conforms to one of
    /// `allowedTypes`, it holds at most `maximumFileSize` bytes, and when it
    /// is allowed as a PDF or an image, its content is one (a file named
    /// .pdf must start like a PDF; an image must decode). Call it while
    /// holding any security-scoped access the file needs.
    nonisolated static func validate(fileAt url: URL, allowedTypes: [UTType]) throws -> CheckedFile {
        let target = url.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isRegularFileKey, .contentTypeKey, .fileSizeKey
        ]
        guard target.isFileURL, let values = try? target.resourceValues(forKeys: keys) else {
            throw Problem.fileMissing
        }
        let isPackage = values.isPackage == true
        if values.isDirectory == true, !isPackage { throw Problem.folder }
        guard values.isRegularFile == true || isPackage else { throw Problem.notAFile }

        let contentType = values.contentType ?? UTType(filenameExtension: target.pathExtension) ?? .data
        guard let matched = allowedTypes.first(where: { contentType.conforms(to: $0) }) else {
            throw Problem.wrongType(allowed: describe(allowedTypes))
        }

        let size = isPackage ? packageSize(target) : Int64(values.fileSize ?? 0)
        guard size <= maximumFileSize else { throw Problem.tooLarge }

        if matched.conforms(to: .pdf) {
            guard startsLikePDF(target) else { throw Problem.notReadable(kind: "a PDF") }
        } else if matched.conforms(to: .image) {
            guard decodesAsImage(target) else { throw Problem.notReadable(kind: "an image") }
        }
        return CheckedFile(url: target, contentType: contentType, size: size)
    }

    /// "a PDF or an image" for `[.pdf, .image]`.
    nonisolated static func describe(_ types: [UTType]) -> String {
        let names = types.map { type -> String in
            switch type {
            case .pdf: return "a PDF"
            case .image: return "an image"
            case .png: return "a PNG image"
            case .jpeg: return "a JPEG image"
            default: return type.localizedDescription.map { "a file of the kind \($0)" } ?? "another kind of file"
            }
        }
        guard let last = names.last else { return "another kind of file" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " or " + last
    }

    /// A PDF's header ("%PDF-") is within its first 1,024 bytes.
    nonisolated private static func startsLikePDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1024) else { return false }
        return head.range(of: Data("%PDF-".utf8)) != nil
    }

    /// ImageIO recognizes the content as an image with at least one frame.
    nonisolated private static func decodesAsImage(_ url: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetType(source) != nil else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// The bytes of every file inside a package.
    nonisolated private static func packageSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
