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

        var isStale = false
        do {
#if os(macOS)
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            )
#else
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            )
#endif

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

    func migrateLegacyLinkedFileIfNeeded() {
        guard lesson.pagesFileRelativePath == nil, lesson.pagesFileBookmark != nil else { return }
        guard let legacyURL = resolvePagesURL(), !LessonFileStorage.isManagedURL(legacyURL) else { return }
        Task(priority: .utility) {
            do {
                guard let lessonID = lesson.id else { return }
                let destURL = try LessonFileStorage.importFile(
                    from: legacyURL,
                    forLessonWithID: lessonID,
                    lessonName: lesson.name
                )
                let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
                let rel = try LessonFileStorage.relativePath(forManagedURL: destURL)
                await MainActor.run {
                    lesson.pagesFileBookmark = bookmark
                    lesson.pagesFileRelativePath = rel
                    resolvedPagesURL = destURL
                    previousManagedURL = destURL
                    saveCoordinator.save(viewContext, reason: "Migrate lesson file to managed storage")
                }
            } catch {
                await MainActor.run { importError = AppErrorMessages.importMessage(for: error, fileType: "lesson file") }
            }
        }
    }

    func savePagesBookmark(from url: URL) {
#if os(iOS)
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#elseif os(macOS)
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lesson.pagesFileBookmark = bookmark
        } catch {
            // ignore error
        }
#endif
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
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
