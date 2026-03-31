import SwiftUI
import CoreData
import OSLog

/// Row view for displaying a single attachment
struct AttachmentRow: View {
    private static let logger = Logger.lessons

    let attachment: CDLessonAttachment
    let isInherited: Bool
    let isPrimary: Bool
    let onTogglePrimary: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

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

                    if isInherited {
                        Image(systemName: attachment.scope.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(attachment.fileSizeFormatted)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            if isHovering || isInherited {
                HStack(spacing: 8) {
                    Button(action: onTogglePrimary) {
                        Image(systemName: isPrimary ? "star.slash" : "star")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help(isPrimary ? "Clear Primary CDLesson File" : "Set as Primary CDLesson File")

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
        }
        .padding(8)
        .background(isHovering ? Color.controlBackgroundColor() : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
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

    private func openAttachment() {
        do {
            let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
            #if os(macOS)
            NSWorkspace.shared.open(fileURL)
            #endif
        } catch {
            Self.logger.error("Failed to open attachment: \(error)")
        }
    }

    private func shareAttachment() {
        do {
            let fileURL = try LessonFileStorage.resolve(relativePath: attachment.fileRelativePath)
            #if os(macOS)
            let picker = NSSharingServicePicker(items: [fileURL])
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
            #endif
        } catch {
            Self.logger.error("Failed to share attachment: \(error)")
        }
    }
}
