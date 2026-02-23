import Foundation
#if os(macOS)
import AppKit
#endif

/// Minimal DOCX merger that edits only word/document.xml.
/// - Important: Preserves all other parts (media, styles) by copying them unchanged.
enum DocxTemplateMerger {
    enum MergerError: Error { case templateNotFound, unzipFailed, documentXMLMissing, ioFailed(String) }

    /// Perform merge into outputURL using replacements. Only word/document.xml is edited.
    static func merge(templateURL: URL, outputURL: URL, replacements: [String: String]) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("docx_merge_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            do {
                try fm.removeItem(at: tempDir)
            } catch {
                print("⚠️ [\(#function)] Failed to remove temp directory: \(error)")
            }
        }

        // 1) Unzip template into temp dir
        try unzipDocx(at: templateURL, to: tempDir)

        // 2) Read word/document.xml
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let documentXML = wordDir.appendingPathComponent("document.xml", isDirectory: false)
        guard fm.fileExists(atPath: documentXML.path) else { throw MergerError.documentXMLMissing }
        var xml = try String(contentsOf: documentXML, encoding: .utf8)

        // 3) Replace placeholders with XML-escaped text; convert newlines to <w:br/>
        for (key, value) in replacements {
            let escaped = xmlEscape(value).replacingOccurrences(of: "\n", with: "</w:t><w:br/><w:t>")
            xml = xml.replacingOccurrences(of: key, with: escaped)
        }
        try xml.write(to: documentXML, atomically: true, encoding: .utf8)

        // 4) Zip directory back to DOCX
        try zipDocx(from: tempDir, to: outputURL)
    }

    // MARK: - Helpers
    private static func xmlEscape(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    // Use /usr/bin/zip and /usr/bin/unzip to avoid third-party deps; available on macOS.
    #if os(macOS)
    private static func unzipDocx(at zipURL: URL, to destDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destDir.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw MergerError.unzipFailed }
    }
    #else
    private static func unzipDocx(at zipURL: URL, to destDir: URL) throws {
        throw MergerError.ioFailed("DOCX merge is only supported on macOS.")
    }
    #endif

    #if os(macOS)
    private static func zipDocx(from sourceDir: URL, to zipURL: URL) throws {
        // Build zip from contents of sourceDir
        let cwd = sourceDir
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -q quiet, -r recursive, -X to strip extra file attributes
        process.arguments = ["-q", "-r", "-X", zipURL.path, "."]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw MergerError.ioFailed("zip failed") }
    }
    #else
    private static func zipDocx(from sourceDir: URL, to zipURL: URL) throws {
        throw MergerError.ioFailed("DOCX merge is only supported on macOS.")
    }
    #endif
}

