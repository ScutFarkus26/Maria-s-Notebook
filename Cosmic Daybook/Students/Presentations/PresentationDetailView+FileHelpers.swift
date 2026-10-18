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

    /// The bookmarked file. Access isn't started here: `openInPages` holds it
    /// while the file is open. Every tap used to start it and nothing stopped
    /// it (review of the 2026-10-17 fixes, a2 #7).
    func resolveBookmarkURL(_ bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        do {
            return try SecurityScopedBookmark.resolve(bookmark).url
        } catch {
            return nil
        }
    }

    /// Opens the file once it is on this device (an iCloud file may still
    /// have to download; see `UbiquitousFile`). On iPhone and iPad, where
    /// `UIApplication.open` can't open a file, the share sheet offers Pages;
    /// `DocumentPresenter` holds access to the file until it closes (bug hunt
    /// 2026-10-17, #22).
    func openInPages(_ url: URL) {
        Task {
#if os(iOS)
            if let message = await DocumentPresenter.open(url, as: .share).message {
                ToastService.shared.showError(message)
            }
#elseif os(macOS)
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            openInPagesOnMac(await UbiquitousFile.localURL(for: url))
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
