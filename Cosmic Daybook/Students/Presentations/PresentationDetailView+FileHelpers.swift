import OSLog
import SwiftUI
import CoreData

nonisolated private let logger = Logger.students

// MARK: - File Management Helpers

extension PresentationDetailContentView {

    func resolveLessonPagesURL() -> URL? {
        guard let lesson = currentLesson else { return nil }

        // Try relative path first
        if let relativePath = lesson.pagesFileRelativePath, !relativePath.isEmpty {
            do {
                let url = try LessonFileStorage.resolve(relativePath: relativePath)
                return url
            } catch {
                logger.warning("Failed to resolve relative path: \(error)")
            }
        }

        // Fallback to bookmark
        return resolveBookmarkURL(lesson.pagesFileBookmark)
    }

    func resolveBookmarkURL(_ bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        do {
            let url = try SecurityScopedBookmark.resolve(bookmark).url
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    /// Opens the file once it is on this device (an iCloud file may still
    /// have to download; see `UbiquitousFile`).
    func openInPages(_ url: URL) {
        Task {
            let url = await UbiquitousFile.localURL(for: url)
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
#if os(iOS)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif os(macOS)
            openInPagesOnMac(url)
#endif
        }
    }

#if os(macOS)
    func openInPagesOnMac(_ url: URL) {
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: pagesAppURL,
                configuration: config,
                completionHandler: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }
#endif
}
