import SwiftUI
import CoreData
import OSLog
import QuickLook

/// Row view for displaying a single attachment.
///
/// On the Mac the actions show on hover, as before. iPhone and iPad have no
/// hover, so there the row carries an actions menu, a tap opens the file in
/// Quick Look, and Share opens the share sheet; the same actions are in the
/// row's context menu everywhere. (They were Mac-only before.)
struct AttachmentRow: View {
    private static let logger = Logger.lessons

    let attachment: CDLessonAttachment
    /// Held by another lesson (shared with the sequence or area): viewable and
    /// shareable here, renamed or deleted from the lesson that holds it.
    let isInherited: Bool
    let isPrimary: Bool
    let onTogglePrimary: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    /// Why the attachment couldn't be opened or shared; the raw error is logged.
    @State private var problemMessage: String?
    /// The file Quick Look is showing (iPhone and iPad).
    @State private var previewURL: URL?

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

                HStack(spacing: 8) {
                    Text(attachment.fileSizeFormatted)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
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
        #if os(iOS)
        .onTapGesture { openAttachment() }
        .quickLookPreview($previewURL)
        #endif
        .contextMenu { menuItems }
        .onHover { hovering in
            isHovering = hovering
        }
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

    @ViewBuilder
    private var menuItems: some View {
        Button { openAttachment() } label: {
            Label("View", systemImage: "eye")
        }
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

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                .fill(fileTypeColor.opacity(UIConstants.OpacityConstants.light))

            Image(systemName: fileTypeIcon)
                .font(.system(size: 16))
                .foregroundStyle(fileTypeColor)
        }
    }

    private var fileTypeColor: Color {
        switch attachment.fileType {
        case "pdf": return .red
        case "pages": return .orange
        case "jpg", "jpeg", "png": return .blue
        default: return .gray
        }
    }

    private var fileTypeIcon: String {
        switch attachment.fileType {
        case "pdf": return "doc.fill"
        case "pages": return "doc.richtext.fill"
        case "jpg", "jpeg", "png": return "photo.fill"
        default: return "doc"
        }
    }

    // MARK: - View and Share

    /// The file once it is on this device (an iCloud file may still have to
    /// download; see `UbiquitousFile`), or nil when it is missing.
    private func readyFileURL() async -> URL? {
        await LessonFileStorage.storage.readyURL(
            bookmark: attachment.fileBookmark, relativePath: attachment.fileRelativePath
        )
    }

    private func openAttachment() {
        Task {
            guard let fileURL = await readyFileURL() else {
                Self.logger.error("Couldn't find an attachment's file to open")
                problemMessage = Self.missingFileMessage
                return
            }
            #if os(macOS)
            if !NSWorkspace.shared.open(fileURL) {
                Self.logger.error("NSWorkspace couldn't open an attachment")
                problemMessage = "Couldn't open this attachment. Try again."
            }
            #else
            previewURL = fileURL
            #endif
        }
    }

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
