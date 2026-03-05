import OSLog
import SwiftUI

private let logger = Logger.students

// MARK: - Independent Workflow Window

#if os(macOS)
struct IndependentWorkflowWindow: View {
    @Bindable var presentationViewModel: PostPresentationFormViewModel
    let students: [Student]
    let lessonName: String
    let lessonID: UUID
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(lessonName) Presentation Workflow")
                    .font(AppTheme.ScaledFont.titleMedium)

                Spacer()

                Button("Close") {
                    dismiss()
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Complete & Save") {
                    onComplete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)

            Divider()

            // Workflow panel (just presentation + work items)
            UnifiedPresentationWorkflowPanel(
                presentationViewModel: presentationViewModel,
                students: students,
                lessonName: lessonName,
                lessonID: lessonID,
                onComplete: {
                    onComplete()
                    dismiss()
                },
                onCancel: {
                    dismiss()
                    onCancel()
                },
                triggerCompletion: nil
            )
        }
    }
}
#endif

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
        guard let bookmark = bookmark else { return nil }
        var stale = false
        do {
#if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
#else
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
#if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif os(macOS)
        openInPagesOnMac(url)
#endif
    }

#if os(macOS)
    func openInPagesOnMac(_ url: URL) {
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
#endif
}
