import SwiftUI

/// Grid card for displaying a resource with PDF thumbnail, title, and category badge.
struct ResourceCard: View {
    let resource: Resource
    let onTap: () -> Void
    let onDelete: () -> Void
    var onRename: (() -> Void)?
    var onChangeCategory: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            thumbnailView
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

            // Title
            Text(resource.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Category + favorite
            HStack(spacing: 4) {
                Image(systemName: resource.category.icon)
                    .font(.caption2)
                Text(resource.category.rawValue)
                    .font(.caption2)

                if resource.isFavorite {
                    Spacer()
                    Image(systemName: SFSymbol.Shape.starFill)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)

            // Tags (show first 2)
            if !resource.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(resource.tags.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                    if resource.tags.count > 2 {
                        Text("+\(resource.tags.count - 2)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onTap) {
                Label("View Details", systemImage: "eye")
            }

            if let onRename {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
            }

            if let onChangeCategory {
                Button(action: onChangeCategory) {
                    Label("Change Category", systemImage: "folder")
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailData = resource.thumbnailData,
           let image = platformImage(from: thumbnailData) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback icon
            VStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.03))
        }
    }

    #if os(macOS)
    private func platformImage(from data: Data) -> Image? {
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }
    #else
    private func platformImage(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
    #endif
}
