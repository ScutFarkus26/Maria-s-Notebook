import OSLog
import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#endif

// MARK: - File Handling

extension LessonDetailView {
    /// The lesson's bookmarked Pages file. Access to it isn't started here:
    /// `openInPages` holds it while the file is open. It used to be started
    /// on every resolve and never stopped (review of the 2026-10-17 fixes,
    /// a2 #7).
    func resolvePagesURL() -> URL? {
        guard let bookmarkData = lesson.pagesFileBookmark else {
            return nil
        }

        do {
            let (url, isStale) = try SecurityScopedBookmark.resolve(
                bookmarkData,
                options: [.withoutUI]
            )

            if isStale {
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
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

    // MARK: - Pages File

    /// Import… in the edit form. The Sample Class can't add files: its
    /// lessons share the real notebook's file folder.
    func beginPagesImport() {
        if isSampleClassroom {
            showingSampleClassFileNotice = true
        } else {
            showingPagesImporter = true
        }
    }

    /// Copies the picked Pages file in and points the lesson at it. The file
    /// it replaces goes to the Trash only once the save has succeeded and no
    /// other lesson uses it; a failed save puts the old file back on the lesson
    /// and removes the copy just made.
    func importPagesFile(from pickedURL: URL) {
        guard !isSampleClassroom else {
            showingSampleClassFileNotice = true
            return
        }
        let needsAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { pickedURL.stopAccessingSecurityScopedResource() } }
        do {
            guard let lessonID = lesson.id else { return }
            let destURL = try LessonFileStorage.importFile(
                from: pickedURL,
                forLessonWithID: lessonID,
                lessonName: lesson.name
            )
            let bookmark = try LessonFileStorage.makeBookmark(for: destURL)
            let rel = try LessonFileStorage.relativePath(forManagedURL: destURL)
            let replacedPath = LessonFileStorage.managedPagesPath(of: lesson)
            let oldBookmark = lesson.pagesFileBookmark
            let oldRelativePath = lesson.pagesFileRelativePath
            lesson.pagesFileBookmark = bookmark
            lesson.pagesFileRelativePath = rel
            guard saveCoordinator.save(viewContext, reason: "Import lesson Pages file") else {
                lesson.pagesFileBookmark = oldBookmark
                lesson.pagesFileRelativePath = oldRelativePath
                try? LessonFileStorage.deleteIfManaged(destURL)
                return
            }
            resolvedPagesURL = destURL
            if let replacedPath {
                LessonFileStorage.trashUnreferencedFiles([replacedPath], in: viewContext, isSampleClassroom: false)
            }
        } catch {
            Self.logger.warning("Pages file import failed: \(error)")
            importError = AppErrorMessages.importMessage(for: error, fileType: "Pages file")
        }
    }

    /// Remove in the edit form: the lesson lets go of its Pages file, and the
    /// file goes to the Trash after the save when nothing else uses it. In the
    /// Sample Class only the record changes.
    func removePagesFile() {
        let removedPath = LessonFileStorage.managedPagesPath(of: lesson)
        let oldBookmark = lesson.pagesFileBookmark
        let oldRelativePath = lesson.pagesFileRelativePath
        lesson.pagesFileBookmark = nil
        lesson.pagesFileRelativePath = nil
        guard saveCoordinator.save(viewContext, reason: "Remove lesson Pages file") else {
            lesson.pagesFileBookmark = oldBookmark
            lesson.pagesFileRelativePath = oldRelativePath
            return
        }
        resolvedPagesURL = nil
        if let removedPath {
            LessonFileStorage.trashUnreferencedFiles(
                [removedPath], in: viewContext, isSampleClassroom: isSampleClassroom
            )
        }
    }

    /// Opens the file once it is on this device (an iCloud file may still
    /// have to download; see `UbiquitousFile`). On iPhone and iPad, where
    /// `UIApplication.open` can't open a file, the share sheet offers Pages;
    /// `DocumentPresenter` holds access to the file until the sheet closes,
    /// since Pages reads the file while the sheet is up.
    func openInPages(_ url: URL) {
        Task {
            #if os(iOS)
            if let message = await DocumentPresenter.open(url, as: .share).message {
                ToastService.shared.showError(message)
            }
            #elseif os(macOS)
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let file = await UbiquitousFile.localURL(for: url)
            if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open(
                    [file], withApplicationAt: pagesAppURL,
                    configuration: config, completionHandler: nil
                )
            } else {
                NSWorkspace.shared.open(file)
            }
            #endif
        }
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
