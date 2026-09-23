import OSLog
import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#endif

// MARK: - File Handling

extension LessonDetailView {
    func resolvePagesURL() -> URL? {
        guard let bookmarkData = lesson.pagesFileBookmark else {
            return nil
        }

        do {
            let (url, isStale) = try SecurityScopedBookmark.resolve(
                bookmarkData,
                options: [.withoutUI]
            )

#if os(iOS)
            if url.startAccessingSecurityScopedResource() {
                // Caller must call stopAccessingSecurityScopedResource when done,
                // but here we keep it open as long as resolvedPagesURL is set.
                // Will be released when resolvedPagesURL changes or view disappears.
            }
#endif

            if isStale {
                // Optionally recreate bookmark here
                savePagesBookmark(from: url)
            }
            return url
        } catch {
            return nil
        }
    }

    func resolveLessonFileURL() -> URL? {
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty {
            do {
                return try LessonFileStorage.resolve(relativePath: rel)
            } catch {
                Self.logger.warning("Failed to resolve relative path: \(error)")
            }
        }
        return resolvePagesURL()
    }

    func savePagesBookmark(from url: URL) {
        do {
            lesson.pagesFileBookmark = try SecurityScopedBookmark.make(for: url)
        } catch {
            // ignore error
        }
    }

    func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [url], withApplicationAt: pagesAppURL,
                configuration: config, completionHandler: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Open In Pages Button

struct OpenInPagesButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.horizontal, AppTheme.Spacing.large - 4)
                .padding(.vertical, AppTheme.Spacing.small)
                .surface(
                    UIConstants.CornerRadius.large,
                    fill: Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
