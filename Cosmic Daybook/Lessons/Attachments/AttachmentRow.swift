import SwiftUI
import CoreData
import OSLog
import QuickLook
import UniformTypeIdentifiers

/// Row view for displaying a single attachment.
///
/// A click (a tap on iPhone and iPad) opens the file in Quick Look. On the Mac
/// the actions show on hover, and the context menu also offers "Open in
/// <app>". iPhone and iPad have no hover, so there the row carries an actions
/// menu; the same actions are in the row's context menu everywhere. Under the
/// name: the size, when the file was added or last updated, and the note
/// saying where it came from, when it has one.
struct AttachmentRow: View {
    private static let logger = Logger.lessons

    let attachment: CDLessonAttachment
    /// Held by another lesson (shared with the sequence or area): viewable and
    /// shareable here, renamed, replaced or deleted from the lesson that holds it.
    let isInherited: Bool
    let isPrimary: Bool
    let onTogglePrimary: () -> Void
    let onRename: () -> Void
    /// Replace with Newer Version…: the card picks the file and replaces it.
    let onReplace: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    /// Why the attachment couldn't be opened or shared; the raw error is logged.
    @State private var problemMessage: String?
    /// The file Quick Look is showing.
    @State private var previewURL: URL?
    #if os(macOS)
    /// "Preview" for a PDF: the app "Open in <app>" names, nil when none is known.
    @State private var defaultAppName: String?
    #endif

    var body: some View {
        HStack(spacing: 12) {
            // File type icon
            fileIcon
                .frame(width: 32, height: 32)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attachment.fileName)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .lineLimit(1)

                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .help("Primary lesson file")
                    }

                    if attachment.scope != .lesson {
                        Image(systemName: attachment.scope.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .help(attachment.scope.description)
                    }
                }

                Text(Self.detailLine(for: attachment))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let note = Self.noteLine(for: attachment) {
                    Text(note)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(note)
                }
            }

            Spacer()

            #if os(macOS)
            if isHovering || isInherited {
                hoverButtons
            }
            #else
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(attachment.fileName)")
            #endif
        }
        .padding(8)
        .background(isHovering ? Color.controlBackgroundColor() : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { openAttachment() }
        .quickLookPreview($previewURL)
        .contextMenu { menuItems }
        .onHover { hovering in
            isHovering = hovering
        }
        #if os(macOS)
        .task(id: attachment.fileType) {
            defaultAppName = Self.defaultAppName(forFileType: attachment.fileType)
        }
        #endif
        .alert("Couldn't Open the Attachment", isPresented: Binding(
            get: { problemMessage != nil },
            set: { if !$0 { problemMessage = nil } }
        )) {
            Button("OK", role: .cancel) { problemMessage = nil }
        } message: {
            Text(problemMessage ?? "")
        }
    }

    private static let missingFileMessage = "Couldn't find this attachment's file. It may have been moved or deleted."
    static let replaceLabel = "Replace with Newer Version…"
    private static let replaceSymbol = "arrow.triangle.2.circlepath"

    @ViewBuilder
    private var menuItems: some View {
        Button { openAttachment() } label: {
            Label("View", systemImage: "eye")
        }
        #if os(macOS)
        Button { openInDefaultApp() } label: {
            Label(
                defaultAppName.map { "Open in \($0)" } ?? "Open in Default App",
                systemImage: "arrow.up.forward.app"
            )
        }
        #endif
        Button { shareAttachment() } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button(action: onTogglePrimary) {
            Label(
                isPrimary ? "Clear Primary Lesson File" : "Set as Primary Lesson File",
                systemImage: isPrimary ? "star.slash" : "star"
            )
        }
        if !isInherited {
            Button(action: onReplace) {
                Label(Self.replaceLabel, systemImage: Self.replaceSymbol)
            }
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    #if os(macOS)
    private var hoverButtons: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePrimary) {
                Image(systemName: isPrimary ? "star.slash" : "star")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help(isPrimary ? "Clear Primary Lesson File" : "Set as Primary Lesson File")

            Button(action: { openAttachment() }, label: {
                Image(systemName: "eye")
                    .font(.system(size: 12))
            })
            .buttonStyle(.borderless)
            .help("View")

            Button(action: { shareAttachment() }, label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
            })
            .buttonStyle(.borderless)
            .help("Share")

            if !isInherited {
                Button(action: onReplace) {
                    Image(systemName: Self.replaceSymbol)
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(Self.replaceLabel)

                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Rename")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.destructive)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
    }
    #endif

    // MARK: - View and Share

    /// The file once its current bytes are on this device, or nil when it is
    /// missing. `readyURL` asks iCloud for the file whenever its status isn't
    /// `.current`, a `.downloaded` copy included (since iOS 18.4 that can be a
    /// stale one), and waits for the coordinated read that brings the current
    /// version down (plan "Lesson file attachments", Decision 9).
    private func readyFileURL() async -> URL? {
        await LessonFileStorage.storage.readyURL(
            bookmark: attachment.fileBookmark, relativePath: attachment.fileRelativePath
        )
    }

    /// Quick Look, on every platform.
    private func openAttachment() {
        Task {
            guard let fileURL = await readyFileURL() else {
                Self.logger.error("Couldn't find an attachment's file to open")
                problemMessage = Self.missingFileMessage
                return
            }
            previewURL = fileURL
        }
    }

    #if os(macOS)
    /// Opens the file in the app the Mac opens its kind with.
    private func openInDefaultApp() {
        Task {
            guard let fileURL = await readyFileURL() else {
                Self.logger.error("Couldn't find an attachment's file to open in another app")
                problemMessage = Self.missingFileMessage
                return
            }
            if !NSWorkspace.shared.open(fileURL) {
                Self.logger.error("NSWorkspace couldn't open an attachment")
                problemMessage = "Couldn't open this attachment. Try again."
            }
        }
    }
    #endif

    private func shareAttachment() {
        Task {
            guard let fileURL = await readyFileURL() else {
                Self.logger.error("Couldn't find an attachment's file to share")
                problemMessage = Self.missingFileMessage
                return
            }
            #if os(macOS)
            let picker = NSSharingServicePicker(items: [fileURL])
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
            #else
            presentShareSheet(for: fileURL)
            #endif
        }
    }

    #if os(iOS)
    /// The system share sheet over whatever is frontmost, anchored mid-window
    /// for the iPad's popover.
    private func presentShareSheet(for fileURL: URL) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var presenter = window.rootViewController else {
            problemMessage = "Couldn't share this attachment. Try again."
            return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }
    #endif
}
